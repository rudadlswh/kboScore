from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field, replace
from typing import Callable, Sequence

import psycopg

from collector.db import advisory_lock
from collector.services.game_upsert_service import GameUpsertService
from collector.services.kbo_schedule_source import KBOScheduleSource, ScheduleSourceRequest
from collector.services.stadium_mapping_service import StadiumMappingService
from collector.services.team_mapping_service import TeamMappingService
from collector.utils.time import now_kst


@dataclass(frozen=True, slots=True)
class ScheduleBootstrapJobInput:
    season_id: int
    months: Sequence[int]


@dataclass(slots=True)
class ScheduleBootstrapJobSummary:
    season_id: int
    months_processed: int = 0
    inserted_count: int = 0
    updated_count: int = 0
    unresolved_team_count: int = 0
    unresolved_stadium_count: int = 0
    errors: list[str] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class ScheduleBootstrapJobDependencies:
    logger: logging.Logger
    db_connection_factory: Callable[[], psycopg.Connection]
    schedule_source: KBOScheduleSource


class ScheduleBootstrapJob:
    job_name = "schedule_bootstrap_job"

    def __init__(self, deps: ScheduleBootstrapJobDependencies) -> None:
        self.deps = deps

    def advisory_lock_name(self, request: ScheduleBootstrapJobInput) -> str:
        return f"{self.job_name}:{request.season_id}"

    def execute(self, request: ScheduleBootstrapJobInput) -> ScheduleBootstrapJobSummary:
        summary = ScheduleBootstrapJobSummary(season_id=request.season_id)
        logger = self.deps.logger
        logger.info("job_started", extra={"job_name": self.job_name, "season_id": request.season_id})

        with self.deps.db_connection_factory() as conn:
            with advisory_lock(conn, self.advisory_lock_name(request)) as locked:
                if not locked:
                    logger.info("job_skipped_lock_held", extra={"job_name": self.job_name})
                    return summary

                observed_at = now_kst()
                team_mapping_service = TeamMappingService(conn)
                stadium_mapping_service = StadiumMappingService()
                game_upsert_service = GameUpsertService(conn)

                for month in request.months:
                    logger.info(
                        "bootstrap_month_started",
                        extra={"job_name": self.job_name, "season_id": request.season_id, "month": month},
                    )

                    try:
                        month_games = self.deps.schedule_source.fetch_month_schedule(
                            ScheduleSourceRequest(season_id=request.season_id, month=month)
                        )

                        month_inserted = 0
                        month_updated = 0
                        for game in month_games:
                            try:
                                home_team_id = team_mapping_service.resolve_team_id(game.home_team_code)
                                away_team_id = team_mapping_service.resolve_team_id(game.away_team_code)
                            except ValueError as error:
                                summary.unresolved_team_count += 1
                                summary.errors.append(str(error))
                                logger.warning(
                                    "bootstrap_unresolved_team",
                                    extra={
                                        "job_name": self.job_name,
                                        "provider_game_id": game.provider_game_id,
                                        "home_team_code": game.home_team_code,
                                        "away_team_code": game.away_team_code,
                                        "error": str(error),
                                    },
                                )
                                continue

                            try:
                                stadium_code = stadium_mapping_service.resolve_stadium_code(game.stadium)
                            except ValueError as error:
                                summary.unresolved_stadium_count += 1
                                summary.errors.append(str(error))
                                logger.warning(
                                    "bootstrap_unresolved_stadium",
                                    extra={
                                        "job_name": self.job_name,
                                        "provider_game_id": game.provider_game_id,
                                        "stadium": game.stadium,
                                        "error": str(error),
                                    },
                                )
                                continue

                            upsert_result = game_upsert_service.upsert_bootstrap_game(
                                game=replace(game, stadium_code=stadium_code),
                                home_team_id=home_team_id,
                                away_team_id=away_team_id,
                                observed_at=observed_at,
                            )
                            if upsert_result.action == "inserted":
                                summary.inserted_count += 1
                                month_inserted += 1
                            elif upsert_result.action == "updated":
                                summary.updated_count += 1
                                month_updated += 1

                        conn.commit()
                        summary.months_processed += 1
                        logger.info(
                            "bootstrap_month_committed",
                            extra={
                                "job_name": self.job_name,
                                "season_id": request.season_id,
                                "month": month,
                                "row_count": len(month_games),
                                "inserted_count": month_inserted,
                                "updated_count": month_updated,
                                "unresolved_team_count": summary.unresolved_team_count,
                                "unresolved_stadium_count": summary.unresolved_stadium_count,
                            },
                        )
                    except Exception:
                        conn.rollback()
                        logger.exception(
                            "bootstrap_month_failed",
                            extra={"job_name": self.job_name, "season_id": request.season_id, "month": month},
                        )
                        raise

        logger.info(
            "job_finished",
            extra={
                "job_name": self.job_name,
                "season_id": request.season_id,
                "months_processed": summary.months_processed,
                "inserted_count": summary.inserted_count,
                "updated_count": summary.updated_count,
                "unresolved_team_count": summary.unresolved_team_count,
                "unresolved_stadium_count": summary.unresolved_stadium_count,
            },
        )
        return summary

    def run_with_retry(
        self,
        request: ScheduleBootstrapJobInput,
        retry_delays_seconds: Sequence[int] = (5, 30, 120),
    ) -> ScheduleBootstrapJobSummary:
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
