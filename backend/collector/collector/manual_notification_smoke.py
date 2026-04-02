from __future__ import annotations

import sys
from datetime import datetime
from typing import Callable

from collector.config import CollectorConfig
from collector.db import connect, wait_for_db
from collector.services.apns_client import APNSClient, APNSConfigurationError, TokenBasedAPNSClient
from collector.services.notification_delivery_service import (
    NotificationDeliveryService,
    NotificationDeliverySummary,
)
from collector.utils.logging import configure_logging, get_logger
from collector.utils.time import now_kst, to_kst


def build_sandbox_apns_client(config: CollectorConfig) -> APNSClient:
    if not config.apns_use_sandbox:
        raise APNSConfigurationError(
            "Manual notification smoke test requires APNS_USE_SANDBOX=true; "
            "refusing to send against production APNs"
        )
    return TokenBasedAPNSClient.from_config(config)


def run_manual_notification_smoke_test(
    *,
    notification_event_id: str,
    config: CollectorConfig,
    logger,
    now_at: datetime | None = None,
    db_connection_factory: Callable[[], object] | None = None,
    apns_client: APNSClient | None = None,
) -> NotificationDeliverySummary:
    delivery_client = apns_client or build_sandbox_apns_client(config)
    observed_at = to_kst(now_at or now_kst())

    with (db_connection_factory or (lambda: connect(config.database_url)))() as conn:
        service = NotificationDeliveryService(conn=conn, apns_client=delivery_client)
        summary = service.deliver_notification_event_by_id(
            notification_event_id=notification_event_id,
            observed_at=observed_at,
            max_attempts=config.notification_delivery_max_attempts,
            retry_delays_seconds=config.notification_retry_delays_seconds,
        )
        conn.commit()

    logger.info(
        "manual_notification_smoke_test_finished",
        extra={
            "notification_event_id": notification_event_id,
            "selected_rows": summary.selected_rows,
            "attempted_rows": summary.attempted_rows,
            "sent_rows": summary.sent_rows,
            "failed_rows": summary.failed_rows,
            "use_sandbox": config.apns_use_sandbox,
        },
    )
    return summary


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    if len(args) != 1:
        print("Usage: python smoke_notification_delivery.py <notification_event_id>", file=sys.stderr)
        return 2

    notification_event_id = args[0]
    config = CollectorConfig.from_env()
    configure_logging(config.log_level)
    logger = get_logger(__name__)

    wait_for_db(config.database_url, logger=logger, retry_seconds=config.db_wait_retry_seconds)
    summary = run_manual_notification_smoke_test(
        notification_event_id=notification_event_id,
        config=config,
        logger=logger,
    )
    return 0 if summary.sent_rows == 1 and summary.failed_rows == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
