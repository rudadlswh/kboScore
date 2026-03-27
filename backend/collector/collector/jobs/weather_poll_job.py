from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Callable, Sequence

import psycopg

from collector.db import advisory_lock
from collector.services.game_upsert_service import GameUpsertService
from collector.services.kbo_weather_source import KBOWeatherSource, WeatherSourceError, WeatherSourceRequest
from collector.services.weather_snapshot_service import WeatherSnapshotService
from collector.utils.hash import sha256_hexdigest
from collector.utils.logging import capture_parse_failure_artifact, log_parse_failure
from collector.utils.time import is_weather_poll_due, to_kst


@dataclass(frozen=True, slots=True)
class WeatherPollJobInput:
    now_at: datetime


@dataclass(slots=True)
class WeatherPollJobSummary:
    due_games: int = 0
    polled_games: int = 0
    inserted_snapshots: int = 0
    skipped_unchanged: int = 0
    parse_failures: int = 0
    errors: list[str] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class WeatherPollJobDependencies:
    logger: logging.Logger
    db_connection_factory: Callable[[], psycopg.Connection]
    weather_source: KBOWeatherSource
    artifact_dir: str = "artifacts"


class WeatherPollJob:
    job_name = "weather_poll_job"

    def __init__(self, deps: WeatherPollJobDependencies) -> None:
        self.deps = deps

    def advisory_lock_name(self, request: WeatherPollJobInput) -> str:
        minute_bucket = request.now_at.strftime("%Y%m%d%H%M")
        return f"{self.job_name}:{minute_bucket}"

    def execute(self, request: WeatherPollJobInput) -> WeatherPollJobSummary:
        summary = WeatherPollJobSummary()
        logger = self.deps.logger
        now_at = to_kst(request.now_at)
        logger.info("job_started", extra={"job_name": self.job_name, "now_at": now_at.isoformat()})

        with self.deps.db_connection_factory() as conn:
            with advisory_lock(conn, self.advisory_lock_name(request)) as locked:
                if not locked:
                    logger.info("job_skipped_lock_held", extra={"job_name": self.job_name})
                    return summary

                weather_snapshot_service = WeatherSnapshotService(conn)
                game_upsert_service = GameUpsertService(conn)
                same_day_games = self._load_same_day_games(conn, now_at.date())
                official_status_map = self._load_official_status_map(now_at.date(), logger)

                for game in same_day_games:
                    if not game["stadium_code"]:
                        logger.warning(
                            "weather_skip_missing_stadium_code",
                            extra={"job_name": self.job_name, "game_id": game["game_id"], "provider_game_id": game["provider_game_id"]},
                        )
                        continue
                    if game["scheduled_at"] is None:
                        logger.warning(
                            "weather_skip_missing_scheduled_at",
                            extra={"job_name": self.job_name, "game_id": game["game_id"], "provider_game_id": game["provider_game_id"]},
                        )
                        continue

                    due, reason = is_weather_poll_due(
                        now_at=now_at,
                        game_date=game["game_date"],
                        scheduled_at=game["scheduled_at"],
                        last_observed_at=game["last_observed_at"],
                    )
                    if not due:
                        logger.info(
                            "weather_not_due",
                            extra={"job_name": self.job_name, "game_id": game["game_id"], "reason": reason},
                        )
                        continue

                    summary.due_games += 1
                    try:
                        snapshot = self.deps.weather_source.fetch_stadium_weather(
                            WeatherSourceRequest(
                                stadium_code=game["stadium_code"],
                                home_code=game["home_team_code"],
                                away_code=game["away_team_code"],
                            )
                        )
                        summary.polled_games += 1
                        inserted = weather_snapshot_service.insert_if_changed(game["game_id"], snapshot)
                        if inserted:
                            summary.inserted_snapshots += 1
                        else:
                            summary.skipped_unchanged += 1

                        official_status = official_status_map.get(
                            (game["stadium_code"], game["home_team_code"], game["away_team_code"])
                        )
                        if official_status is not None and official_status.game_sc == "4":
                            game_upsert_service.mark_game_postponed(game["game_id"], snapshot.source_observed_at)
                    except WeatherSourceError as error:
                        summary.parse_failures += 1
                        summary.errors.append(str(error))
                        artifact_path, response_hash = capture_parse_failure_artifact(
                            base_dir=self.deps.artifact_dir,
                            job_name=self.job_name,
                            source_name=error.source_name,
                            game_id=game["game_id"],
                            observed_at=now_at,
                            response_text=error.response_text,
                        )
                        if artifact_path is None:
                            response_hash = response_hash or sha256_hexdigest("")
                        log_parse_failure(
                            logger,
                            job_name=self.job_name,
                            source_name=error.source_name,
                            game_id=game["game_id"],
                            provider_game_id=game["provider_game_id"],
                            game_date=game["game_date"].isoformat(),
                            observed_at=now_at.isoformat(),
                            error_class=error.__class__.__name__,
                            error_message=str(error),
                            artifact_path=artifact_path,
                            response_hash=response_hash,
                        )
                        continue

                conn.commit()

        logger.info(
            "job_finished",
            extra={
                "job_name": self.job_name,
                "due_games": summary.due_games,
                "polled_games": summary.polled_games,
                "inserted_snapshots": summary.inserted_snapshots,
                "skipped_unchanged": summary.skipped_unchanged,
                "parse_failures": summary.parse_failures,
            },
        )
        return summary

    def run_with_retry(
        self,
        request: WeatherPollJobInput,
        retry_delays_seconds: Sequence[int] = (10, 30),
    ) -> WeatherPollJobSummary:
        attempts = (0, *retry_delays_seconds)
        last_error: Exception | None = None
        for delay in attempts:
            if delay:
                time.sleep(delay)
            try:
                return self.execute(request)
            except Exception as error:  # pragma: no cover - integration-time behavior
                last_error = error
                self.deps.logger.exception("job_retryable_failure", extra={"job_name": self.job_name, "delay": delay})
        assert last_error is not None
        raise last_error

    def _load_same_day_games(self, conn: psycopg.Connection, game_date: date) -> list[dict]:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    g.id::text AS game_id,
                    g.provider_game_id,
                    g.game_date,
                    g.scheduled_at,
                    g.stadium,
                    g.stadium_code,
                    g.status,
                    home.code AS home_team_code,
                    away.code AS away_team_code,
                    latest_snapshot.observed_at AS last_observed_at
                FROM games g
                JOIN teams home ON home.id = g.home_team_id
                JOIN teams away ON away.id = g.away_team_id
                LEFT JOIN LATERAL (
                    SELECT observed_at
                    FROM weather_snapshots
                    WHERE game_id = g.id
                    ORDER BY observed_at DESC
                    LIMIT 1
                ) latest_snapshot ON TRUE
                WHERE g.game_date = %s
                  AND g.status IN ('scheduled', 'live', 'postponed')
                ORDER BY g.scheduled_at ASC NULLS LAST, g.id ASC
                """,
                (game_date,),
            )
            return list(cur.fetchall())

    def _load_official_status_map(
        self,
        game_date: date,
        logger: logging.Logger,
    ) -> dict[tuple[str, str | None, str | None], object]:
        try:
            return self.deps.weather_source.fetch_today_game_statuses(game_date)
        except Exception as error:
            logger.warning(
                "weather_status_supplement_unavailable",
                extra={"job_name": self.job_name, "game_date": game_date.isoformat(), "error": str(error)},
            )
            return {}
