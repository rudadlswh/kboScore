from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Mapping

import psycopg

from collector.db import connect


@dataclass(frozen=True, slots=True)
class ManualNotificationPreflightResult:
    ready: bool
    errors: list[str] = field(default_factory=list)
    eligible_device_count: int = 0
    queued_notification_count: int = 0
    target_notification_ready: bool = False


def run_manual_notification_preflight(
    *,
    env: Mapping[str, str] | None = None,
    notification_event_id: str | None = None,
    db_connection_factory: Callable[[], psycopg.Connection] | None = None,
) -> ManualNotificationPreflightResult:
    env_map = env or os.environ
    errors: list[str] = []

    database_url = env_map.get("DATABASE_URL", "").strip()
    apns_team_id = env_map.get("APNS_TEAM_ID", "").strip()
    apns_key_id = env_map.get("APNS_KEY_ID", "").strip()
    apns_bundle_id = env_map.get("APNS_BUNDLE_ID", "").strip()
    apns_private_key_path = env_map.get("APNS_PRIVATE_KEY_PATH", "").strip()
    apns_use_sandbox = env_map.get("APNS_USE_SANDBOX", "").strip()

    if not database_url:
        errors.append("Missing required env var: DATABASE_URL")
    if not apns_team_id:
        errors.append("Missing required env var: APNS_TEAM_ID")
    if not apns_key_id:
        errors.append("Missing required env var: APNS_KEY_ID")
    if not apns_bundle_id:
        errors.append("Missing required env var: APNS_BUNDLE_ID")
    if not apns_private_key_path:
        errors.append("Missing required env var: APNS_PRIVATE_KEY_PATH")
    if not apns_use_sandbox:
        errors.append("Missing required env var: APNS_USE_SANDBOX")
    elif apns_use_sandbox.lower() not in {"1", "true", "yes", "on"}:
        errors.append("APNS_USE_SANDBOX must be true for the manual sandbox smoke test")

    if apns_private_key_path:
        key_path = Path(apns_private_key_path)
        if not key_path.exists():
            errors.append(f"APNS private key file does not exist: {apns_private_key_path}")
        elif not key_path.is_file():
            errors.append(f"APNS private key path is not a file: {apns_private_key_path}")
        elif not os.access(key_path, os.R_OK):
            errors.append(f"APNS private key file is not readable: {apns_private_key_path}")

    eligible_device_count = 0
    queued_notification_count = 0
    target_notification_ready = False

    if database_url:
        try:
            with (db_connection_factory or (lambda: connect(database_url)))() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        SELECT COUNT(*) AS count
                        FROM device_registrations
                        WHERE notifications_enabled = TRUE
                          AND NULLIF(BTRIM(device_token), '') IS NOT NULL
                        """
                    )
                    eligible_device_count = int(cur.fetchone()["count"])

                    cur.execute(
                        """
                        SELECT COUNT(*) AS count
                        FROM notification_events
                        WHERE delivery_status = 'queued'
                        """
                    )
                    queued_notification_count = int(cur.fetchone()["count"])

                    if notification_event_id is not None:
                        cur.execute(
                            """
                            SELECT COUNT(*) AS count
                            FROM notification_events
                            WHERE id = %(notification_event_id)s::uuid
                              AND delivery_status = 'queued'
                            """,
                            {"notification_event_id": notification_event_id},
                        )
                        target_notification_ready = int(cur.fetchone()["count"]) > 0
        except Exception as error:
            errors.append(f"Database preflight failed: {error.__class__.__name__}: {error}")

    if database_url and eligible_device_count < 1:
        errors.append("No eligible device_registrations rows found for the smoke test")
    if database_url and queued_notification_count < 1:
        errors.append("No queued notification_events rows found for the smoke test")
    if database_url and notification_event_id is not None and not target_notification_ready:
        errors.append(f"Target notification_event_id is missing or not queued: {notification_event_id}")

    return ManualNotificationPreflightResult(
        ready=not errors,
        errors=errors,
        eligible_device_count=eligible_device_count,
        queued_notification_count=queued_notification_count,
        target_notification_ready=target_notification_ready,
    )


def main(argv: list[str] | None = None) -> int:
    notification_event_id = argv[0] if argv else None
    result = run_manual_notification_preflight(notification_event_id=notification_event_id)
    if result.ready:
        print("Smoke-test preflight ready")
        print(f"eligible_device_count={result.eligible_device_count}")
        print(f"queued_notification_count={result.queued_notification_count}")
        if notification_event_id is not None:
            print(f"target_notification_ready={str(result.target_notification_ready).lower()}")
        return 0

    for error in result.errors:
        print(error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(os.sys.argv[1:]))
