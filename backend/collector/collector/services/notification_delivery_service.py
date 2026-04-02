from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

import psycopg

from collector.services.apns_client import APNSClient, APNSDeliveryError, APNSNotificationRequest
from collector.utils.time import to_kst


class NotificationDeliveryTargetError(RuntimeError):
    """Raised when a specific notification ledger row cannot be delivered safely."""


@dataclass(frozen=True, slots=True)
class NotificationDeliverySummary:
    selected_rows: int
    attempted_rows: int
    sent_rows: int
    failed_rows: int


@dataclass(slots=True)
class NotificationDeliveryService:
    conn: psycopg.Connection
    apns_client: APNSClient

    def deliver_queued_notifications(
        self,
        *,
        observed_at: datetime,
        batch_size: int = 100,
        max_attempts: int = 3,
        retry_delays_seconds: tuple[int, ...] = (60, 300),
    ) -> NotificationDeliverySummary:
        observed_at = to_kst(observed_at)
        rows = self._load_delivery_candidates(
            observed_at=observed_at,
            batch_size=batch_size,
            max_attempts=max_attempts,
        )
        return self._deliver_rows(
            rows=rows,
            observed_at=observed_at,
            max_attempts=max_attempts,
            retry_delays_seconds=retry_delays_seconds,
        )

    def deliver_notification_event_by_id(
        self,
        *,
        notification_event_id: str,
        observed_at: datetime,
        max_attempts: int = 3,
        retry_delays_seconds: tuple[int, ...] = (60, 300),
    ) -> NotificationDeliverySummary:
        observed_at = to_kst(observed_at)
        row = self._load_delivery_target(notification_event_id=notification_event_id)
        if row is None:
            raise NotificationDeliveryTargetError(
                f"Queued notification event not found for manual delivery: {notification_event_id}"
            )
        return self._deliver_rows(
            rows=[row],
            observed_at=observed_at,
            max_attempts=max_attempts,
            retry_delays_seconds=retry_delays_seconds,
        )

    def _deliver_rows(
        self,
        *,
        rows: list[dict],
        observed_at: datetime,
        max_attempts: int,
        retry_delays_seconds: tuple[int, ...],
    ) -> NotificationDeliverySummary:
        attempted_rows = 0
        sent_rows = 0
        failed_rows = 0

        for row in rows:
            attempted_rows += 1
            failure_reason = self._preflight_failure_reason(row)
            if failure_reason is not None:
                self._mark_failed(
                    row["id"],
                    observed_at=observed_at,
                    reason=failure_reason,
                    retryable=False,
                    attempt_count=int(row["attempt_count"]),
                    max_attempts=max_attempts,
                    retry_delays_seconds=retry_delays_seconds,
                    device_registration_id=row["device_registration_id"],
                    disable_device=False,
                )
                failed_rows += 1
                continue

            try:
                self.apns_client.send_notification(
                    APNSNotificationRequest(
                        device_token=str(row["device_token"]),
                        title=row["title"],
                        body=row["body"],
                        payload_json=dict(row["payload_json"] or {}),
                    )
                )
            except APNSDeliveryError as error:
                self._mark_failed(
                    row["id"],
                    observed_at=observed_at,
                    reason=error.reason,
                    retryable=error.retryable,
                    attempt_count=int(row["attempt_count"]),
                    max_attempts=max_attempts,
                    retry_delays_seconds=retry_delays_seconds,
                    device_registration_id=row["device_registration_id"],
                    disable_device=error.disable_device,
                )
                failed_rows += 1
                continue

            self._mark_sent(row["id"], observed_at=observed_at)
            sent_rows += 1

        return NotificationDeliverySummary(
            selected_rows=len(rows),
            attempted_rows=attempted_rows,
            sent_rows=sent_rows,
            failed_rows=failed_rows,
        )

    def _load_delivery_target(self, *, notification_event_id: str) -> dict | None:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    ne.id::text AS id,
                    ne.title,
                    ne.body,
                    ne.payload_json,
                    ne.device_registration_id::text AS device_registration_id,
                    ne.attempt_count,
                    ne.next_attempt_at,
                    ne.delivery_status,
                    dr.device_token,
                    dr.notifications_enabled
                FROM notification_events ne
                LEFT JOIN device_registrations dr ON dr.id = ne.device_registration_id
                WHERE ne.id = %(notification_event_id)s::uuid
                  AND ne.delivery_status = 'queued'
                LIMIT 1
                """,
                {"notification_event_id": notification_event_id},
            )
            return cur.fetchone()

    def _load_delivery_candidates(
        self,
        *,
        observed_at: datetime,
        batch_size: int,
        max_attempts: int,
    ) -> list[dict]:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    ne.id::text AS id,
                    ne.title,
                    ne.body,
                    ne.payload_json,
                    ne.device_registration_id::text AS device_registration_id,
                    ne.attempt_count,
                    ne.next_attempt_at,
                    ne.delivery_status,
                    dr.device_token,
                    dr.notifications_enabled
                FROM notification_events ne
                LEFT JOIN device_registrations dr ON dr.id = ne.device_registration_id
                WHERE (
                        ne.delivery_status = 'queued'
                    OR (
                        ne.delivery_status = 'failed'
                        AND ne.next_attempt_at IS NOT NULL
                        AND ne.next_attempt_at <= %(observed_at)s
                        AND ne.attempt_count < %(max_attempts)s
                    )
                )
                ORDER BY
                    COALESCE(ne.next_attempt_at, ne.created_at) ASC,
                    ne.created_at ASC,
                    ne.id ASC
                LIMIT %(batch_size)s
                """,
                {
                    "observed_at": observed_at,
                    "max_attempts": max_attempts,
                    "batch_size": batch_size,
                },
            )
            return list(cur.fetchall())

    @staticmethod
    def _preflight_failure_reason(row: dict) -> str | None:
        if row["device_registration_id"] is None:
            return "missing_device_registration"
        if row["notifications_enabled"] is not True:
            return "notifications_disabled"
        token = row["device_token"]
        if token is None:
            return "missing_device_token"
        if not str(token).strip():
            return "blank_device_token"
        return None

    def _mark_sent(self, notification_event_id: str, *, observed_at: datetime) -> None:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE notification_events
                SET
                    delivery_status = 'sent',
                    attempted_at = %(observed_at)s,
                    sent_at = %(observed_at)s,
                    failed_at = NULL,
                    failure_reason = NULL,
                    next_attempt_at = NULL,
                    attempt_count = attempt_count + 1
                WHERE id = %(notification_event_id)s::uuid
                """,
                {
                    "observed_at": observed_at,
                    "notification_event_id": notification_event_id,
                },
            )

    def _mark_failed(
        self,
        notification_event_id: str,
        *,
        observed_at: datetime,
        reason: str,
        retryable: bool,
        attempt_count: int,
        max_attempts: int,
        retry_delays_seconds: tuple[int, ...],
        device_registration_id: str | None,
        disable_device: bool,
    ) -> None:
        next_attempt_at = self._next_attempt_at(
            observed_at=observed_at,
            retryable=retryable,
            attempt_count=attempt_count,
            max_attempts=max_attempts,
            retry_delays_seconds=retry_delays_seconds,
        )

        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE notification_events
                SET
                    delivery_status = 'failed',
                    attempted_at = %(observed_at)s,
                    failed_at = %(observed_at)s,
                    failure_reason = %(reason)s,
                    next_attempt_at = %(next_attempt_at)s,
                    attempt_count = attempt_count + 1
                WHERE id = %(notification_event_id)s::uuid
                """,
                {
                    "observed_at": observed_at,
                    "reason": reason,
                    "next_attempt_at": next_attempt_at,
                    "notification_event_id": notification_event_id,
                },
            )
        if disable_device and device_registration_id is not None:
            self._disable_device_registration(device_registration_id=device_registration_id)

    def _disable_device_registration(self, *, device_registration_id: str) -> None:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE device_registrations
                SET notifications_enabled = FALSE
                WHERE id = %s::uuid
                """,
                (device_registration_id,),
            )

    @staticmethod
    def _next_attempt_at(
        *,
        observed_at: datetime,
        retryable: bool,
        attempt_count: int,
        max_attempts: int,
        retry_delays_seconds: tuple[int, ...],
    ) -> datetime | None:
        next_attempt_count = attempt_count + 1
        if not retryable or next_attempt_count >= max_attempts:
            return None

        if retry_delays_seconds:
            index = min(max(next_attempt_count - 1, 0), len(retry_delays_seconds) - 1)
            delay_seconds = retry_delays_seconds[index]
        else:
            delay_seconds = 60
        return observed_at + timedelta(seconds=delay_seconds)
