from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Sequence

import psycopg

from collector.db import advisory_lock
from collector.services.notification_service import NotificationService
from collector.utils.time import to_kst


@dataclass(frozen=True, slots=True)
class ConfirmedRainoutNotifyJobInput:
    now_at: datetime


@dataclass(slots=True)
class ConfirmedRainoutNotifyJobSummary:
    candidate_games: int = 0
    target_devices: int = 0
    inserted_notification_events: int = 0
    skipped_duplicates: int = 0
    errors: list[str] = field(default_factory=list)


@dataclass(frozen=True, slots=True)
class ConfirmedRainoutNotifyJobDependencies:
    logger: logging.Logger
    db_connection_factory: Callable[[], psycopg.Connection]


class ConfirmedRainoutNotifyJob:
    job_name = "confirmed_rainout_notify_job"

    def __init__(self, deps: ConfirmedRainoutNotifyJobDependencies) -> None:
        self.deps = deps

    def advisory_lock_name(self, request: ConfirmedRainoutNotifyJobInput) -> str:
        minute_bucket = request.now_at.strftime("%Y%m%d%H%M")
        return f"{self.job_name}:{minute_bucket}"

    def execute(self, request: ConfirmedRainoutNotifyJobInput) -> ConfirmedRainoutNotifyJobSummary:
        summary = ConfirmedRainoutNotifyJobSummary()
        logger = self.deps.logger
        now_at = to_kst(request.now_at)
        logger.info("job_started", extra={"job_name": self.job_name, "now_at": now_at.isoformat()})

        with self.deps.db_connection_factory() as conn:
            with advisory_lock(conn, self.advisory_lock_name(request)) as locked:
                if not locked:
                    logger.info("job_skipped_lock_held", extra={"job_name": self.job_name})
                    return summary

                notification_service = NotificationService(conn)
                service_summary = notification_service.create_confirmed_rainout_notification_events(now_at)
                summary.candidate_games = service_summary.candidate_games
                summary.target_devices = service_summary.target_devices
                summary.inserted_notification_events = service_summary.inserted_notification_events
                summary.skipped_duplicates = service_summary.skipped_duplicates
                conn.commit()

        logger.info(
            "job_finished",
            extra={
                "job_name": self.job_name,
                "candidate_games": summary.candidate_games,
                "target_devices": summary.target_devices,
                "inserted_notification_events": summary.inserted_notification_events,
                "skipped_duplicates": summary.skipped_duplicates,
            },
        )
        return summary

    def run_with_retry(
        self,
        request: ConfirmedRainoutNotifyJobInput,
        retry_delays_seconds: Sequence[int] = (),
    ) -> ConfirmedRainoutNotifyJobSummary:
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
        if last_error is not None:
            raise last_error
        return self.execute(request)
