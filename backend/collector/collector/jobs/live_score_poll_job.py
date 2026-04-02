from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Callable, Sequence

import psycopg

from collector.db import advisory_lock
from collector.services.game_upsert_service import GameUpsertService
from collector.services.kbo_scoreboard_source import (
    KBOScoreboardSource,
    LiveScoreSourceError,
    LiveScoreSourceRequest,
)
from collector.services.live_snapshot_service import LiveSnapshotService
from collector.utils.hash import sha256_hexdigest
from collector.utils.logging import capture_parse_failure_artifact, log_parse_failure
from collector.utils.time import to_kst


@dataclass(frozen=True, slots=True)
class LiveScorePollJobInput:
    now_at: datetime


@dataclass(slots=True)
class LiveScorePollJobSummary:
    candidate_games: int = 0
    polled_games: int = 0
    inserted_snapshots: int = 0
    skipped_unchanged: int = 0
    canonical_updates: int = 0
    parse_failures: int = 0
    errors: list[str] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class LiveScorePollJobDependencies:
    logger: logging.Logger
    db_connection_factory: Callable[[], psycopg.Connection]
    scoreboard_source: KBOScoreboardSource
    artifact_dir: str = "artifacts"


class LiveScorePollJob:
    job_name = "live_score_poll_job"

    def __init__(self, deps: LiveScorePollJobDependencies) -> None:
        self.deps = deps

    def advisory_lock_name(self, request: LiveScorePollJobInput) -> str:
        second_bucket = request.now_at.strftime("%Y%m%d%H%M%S")
        return f"{self.job_name}:{second_bucket}"

    def execute(self, request: LiveScorePollJobInput) -> LiveScorePollJobSummary:
        summary = LiveScorePollJobSummary()
        logger = self.deps.logger
        now_at = to_kst(request.now_at)
        logger.info("job_started", extra={"job_name": self.job_name, "now_at": now_at.isoformat()})

        with self.deps.db_connection_factory() as conn:
            with advisory_lock(conn, self.advisory_lock_name(request)) as locked:
                if not locked:
                    logger.info("job_skipped_lock_held", extra={"job_name": self.job_name})
                    return summary

                candidate_games = self._load_candidate_games(conn, now_at)
                summary.candidate_games = len(candidate_games)
                logger.info(
                    "live_poll_candidates_loaded",
                    extra={
                        "job_name": self.job_name,
                        "candidate_games": summary.candidate_games,
                        "skipped_games": self._count_skipped_same_day_games(conn, now_at.date(), summary.candidate_games),
                    },
                )

                if not candidate_games:
                    return summary

                live_snapshot_service = LiveSnapshotService(conn)
                game_upsert_service = GameUpsertService(conn)

                try:
                    states = self.deps.scoreboard_source.fetch_live_game_states(
                        LiveScoreSourceRequest(game_date=now_at.date())
                    )
                except LiveScoreSourceError as error:
                    summary.parse_failures += 1
                    summary.errors.append(str(error))
                    artifact_path, response_hash = capture_parse_failure_artifact(
                        base_dir=self.deps.artifact_dir,
                        job_name=self.job_name,
                        source_name=error.source_name,
                        game_id="all",
                        observed_at=now_at,
                        response_text=error.response_text,
                    )
                    if artifact_path is None:
                        response_hash = response_hash or sha256_hexdigest("")
                    log_parse_failure(
                        logger,
                        job_name=self.job_name,
                        source_name=error.source_name,
                        game_id="all",
                        provider_game_id="all",
                        game_date=now_at.date().isoformat(),
                        observed_at=now_at.isoformat(),
                        error_class=error.__class__.__name__,
                        error_message=str(error),
                        artifact_path=artifact_path,
                        response_hash=response_hash,
                    )
                    return summary

                state_by_provider_game_ref = {state.provider_game_ref: state for state in states}

                for game in candidate_games:
                    state = state_by_provider_game_ref.get(game["official_provider_game_id"] or game["provider_game_id"])
                    if state is None and game["official_provider_game_id"]:
                        state = state_by_provider_game_ref.get(game["provider_game_id"])
                    if state is None:
                        logger.info(
                            "live_state_missing_for_candidate",
                            extra={
                                "job_name": self.job_name,
                                "game_id": game["game_id"],
                                "provider_game_id": game["provider_game_id"],
                            },
                        )
                        continue

                    logger.info(
                        "live_poll_state_received",
                        extra={
                            "job_name": self.job_name,
                            "game_id": game["game_id"],
                            "provider_game_ref": state.provider_game_ref,
                            "provider_raw_status": state.phase_text,
                            "mapped_status": state.status,
                            "inning_label": state.inning_label,
                        },
                    )

                    summary.polled_games += 1
                    inserted = live_snapshot_service.insert_if_changed(game["game_id"], state)
                    if inserted:
                        summary.inserted_snapshots += 1
                    else:
                        summary.skipped_unchanged += 1
                    logger.info(
                        "live_poll_snapshot_result",
                        extra={
                            "job_name": self.job_name,
                            "game_id": game["game_id"],
                            "snapshot_inserted": inserted,
                            "snapshot_status": state.status,
                        },
                    )

                    if state.is_postponed():
                        updated = game_upsert_service.mark_game_postponed(
                            game["game_id"],
                            state.source_observed_at,
                            source=state.source_name,
                            reason="rain" if state.cancel_reason_text and "우천" in state.cancel_reason_text else None,
                            payload_json={
                                "provider_game_ref": state.provider_game_ref,
                                "cancel_reason_text": state.cancel_reason_text,
                                "final_reason_text": state.final_reason_text,
                            },
                        )
                    else:
                        updated = game_upsert_service.apply_live_game_update(
                            game["game_id"],
                            state,
                            state.source_observed_at,
                        )
                    if updated:
                        summary.canonical_updates += 1
                    logger.info(
                        "live_poll_canonical_status_result",
                        extra={
                            "job_name": self.job_name,
                            "game_id": game["game_id"],
                            "snapshot_status": state.status,
                            "canonical_updated": updated,
                        },
                    )

                conn.commit()

        logger.info(
            "job_finished",
            extra={
                "job_name": self.job_name,
                "candidate_games": summary.candidate_games,
                "polled_games": summary.polled_games,
                "inserted_snapshots": summary.inserted_snapshots,
                "skipped_unchanged": summary.skipped_unchanged,
                "canonical_updates": summary.canonical_updates,
                "parse_failures": summary.parse_failures,
            },
        )
        return summary

    def run_with_retry(
        self,
        request: LiveScorePollJobInput,
        retry_delays_seconds: Sequence[int] = (2,),
    ) -> LiveScorePollJobSummary:
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

    def _load_candidate_games(self, conn: psycopg.Connection, now_at: datetime) -> list[dict]:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    g.id::text AS game_id,
                    g.provider_game_id,
                    g.official_provider_game_id,
                    g.game_date,
                    g.scheduled_at,
                    g.status,
                    g.source_updated_at
                FROM games g
                WHERE g.game_date = %s
                  AND (
                    g.status = 'live'
                    OR (
                        g.status NOT IN ('finished', 'postponed', 'cancelled')
                        AND g.scheduled_at IS NOT NULL
                        AND g.scheduled_at <= %s + interval '15 minutes'
                    )
                    OR (
                        g.status NOT IN ('finished', 'postponed', 'cancelled')
                        AND g.scheduled_at IS NOT NULL
                        AND g.scheduled_at <= %s
                    )
                  )
                ORDER BY g.scheduled_at ASC NULLS LAST, g.id ASC
                """,
                (now_at.date(), now_at, now_at),
            )
            return list(cur.fetchall())

    def _count_skipped_same_day_games(self, conn: psycopg.Connection, game_date: date, selected_count: int) -> int:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*) AS count
                FROM games
                WHERE game_date = %s
                """,
                (game_date,),
            )
            row = cur.fetchone()
        total = int(row["count"]) if row is not None else 0
        return max(total - selected_count, 0)
