from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Sequence

import psycopg

from collector.db import advisory_lock
from collector.services.apns_client import APNSClient
from collector.services.notification_delivery_service import NotificationDeliveryService
from collector.utils.time import to_kst


@dataclass(frozen=True, slots=True)
class NotificationDeliveryJobInput:
    now_at: datetime
    batch_size: int = 100
    max_attempts: int = 3
    retry_delays_seconds: tuple[int, ...] = (60, 300)


@dataclass(slots=True)
class NotificationDeliveryJobSummary:
    selected_rows: int = 0
    attempted_rows: int = 0
    sent_rows: int = 0
    failed_rows: int = 0


@dataclass(frozen=True, slots=True)
class NotificationDeliveryJobDependencies:
    logger: logging.Logger
    db_connection_factory: Callable[[], psycopg.Connection]
    apns_client: APNSClient


class NotificationDeliveryJob:
    job_name = "notification_delivery_job"

    def __init__(self, deps: NotificationDeliveryJobDependencies) -> None:
        self.deps = deps

    def advisory_lock_name(self, request: NotificationDeliveryJobInput) -> str:
        minute_bucket = request.now_at.strftime("%Y%m%d%H%M")
        return f"{self.job_name}:{minute_bucket}"

    def execute(self, request: NotificationDeliveryJobInput) -> NotificationDeliveryJobSummary:
        summary = NotificationDeliveryJobSummary()
        logger = self.deps.logger
        now_at = to_kst(request.now_at)
        logger.info("job_started", extra={"job_name": self.job_name, "now_at": now_at.isoformat()})

        with self.deps.db_connection_factory() as conn:
            with advisory_lock(conn, self.advisory_lock_name(request)) as locked:
                if not locked:
                    logger.info("job_skipped_lock_held", extra={"job_name": self.job_name})
                    return summary

                service = NotificationDeliveryService(conn=conn, apns_client=self.deps.apns_client)
                service_summary = service.deliver_queued_notifications(
                    observed_at=now_at,
                    batch_size=request.batch_size,
                    max_attempts=request.max_attempts,
                    retry_delays_seconds=request.retry_delays_seconds,
                )
                summary.selected_rows = service_summary.selected_rows
                summary.attempted_rows = service_summary.attempted_rows
                summary.sent_rows = service_summary.sent_rows
                summary.failed_rows = service_summary.failed_rows
                conn.commit()

        logger.info(
            "job_finished",
            extra={
                "job_name": self.job_name,
                "selected_rows": summary.selected_rows,
                "attempted_rows": summary.attempted_rows,
                "sent_rows": summary.sent_rows,
                "failed_rows": summary.failed_rows,
            },
        )
        return summary

    def run_with_retry(
        self,
        request: NotificationDeliveryJobInput,
        retry_delays_seconds: Sequence[int] = (),
    ) -> NotificationDeliveryJobSummary:
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
