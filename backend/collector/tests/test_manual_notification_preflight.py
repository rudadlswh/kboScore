from __future__ import annotations

from datetime import datetime

from collector.manual_notification_preflight import run_manual_notification_preflight
from collector.manual_notification_setup import seed_manual_notification_smoke_target
from collector.utils.time import KST
from tests.helpers.db_seed import insert_device_registration, seed_default_teams


def _env(*, key_path: str, database_url: str = "postgresql://placeholder") -> dict[str, str]:
    return {
        "DATABASE_URL": database_url,
        "APNS_TEAM_ID": "TEAM123",
        "APNS_KEY_ID": "KEY123",
        "APNS_BUNDLE_ID": "com.kbo.score",
        "APNS_PRIVATE_KEY_PATH": key_path,
        "APNS_USE_SANDBOX": "true",
    }


def test_preflight_checker_reports_missing_env_vars_clearly():
    result = run_manual_notification_preflight(env={})

    assert result.ready is False
    assert "Missing required env var: DATABASE_URL" in result.errors
    assert "Missing required env var: APNS_TEAM_ID" in result.errors
    assert "Missing required env var: APNS_KEY_ID" in result.errors
    assert "Missing required env var: APNS_BUNDLE_ID" in result.errors
    assert "Missing required env var: APNS_PRIVATE_KEY_PATH" in result.errors
    assert "Missing required env var: APNS_USE_SANDBOX" in result.errors


def test_preflight_checker_reports_missing_p8_path_clearly(tmp_path, db_connection_factory):
    missing_key_path = tmp_path / "missing-key.p8"

    result = run_manual_notification_preflight(
        env=_env(key_path=str(missing_key_path)),
        db_connection_factory=db_connection_factory,
    )

    assert result.ready is False
    assert f"APNS private key file does not exist: {missing_key_path}" in result.errors


def test_preflight_checker_reports_missing_eligible_device_clearly(tmp_path, db_connection_factory):
    key_path = tmp_path / "AuthKey_TEST.p8"
    key_path.write_text("test-key", encoding="utf-8")

    result = run_manual_notification_preflight(
        env=_env(key_path=str(key_path)),
        db_connection_factory=db_connection_factory,
    )

    assert result.ready is False
    assert "No eligible device_registrations rows found for the smoke test" in result.errors


def test_preflight_checker_reports_missing_queued_notification_clearly(tmp_path, db_connection_factory):
    key_path = tmp_path / "AuthKey_TEST.p8"
    key_path.write_text("test-key", encoding="utf-8")

    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        insert_device_registration(
            conn,
            device_token="sandbox-device-token",
            favorite_team_id=team_ids["LG"],
            notifications_enabled=True,
        )

    result = run_manual_notification_preflight(
        env=_env(key_path=str(key_path)),
        db_connection_factory=db_connection_factory,
    )

    assert result.ready is False
    assert result.eligible_device_count == 1
    assert "No queued notification_events rows found for the smoke test" in result.errors


def test_seed_setup_helper_creates_only_one_explicit_target_row_and_device(db_connection_factory):
    first = seed_manual_notification_smoke_target(
        database_url="postgresql://placeholder",
        device_token="sandbox-device-token",
        now_at=datetime(2026, 3, 28, 17, 0, tzinfo=KST),
        db_connection_factory=db_connection_factory,
    )
    second = seed_manual_notification_smoke_target(
        database_url="postgresql://placeholder",
        device_token="sandbox-device-token",
        now_at=datetime(2026, 3, 28, 17, 0, tzinfo=KST),
        db_connection_factory=db_connection_factory,
    )

    with db_connection_factory() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) AS count FROM device_registrations WHERE device_token = %s",
                ("sandbox-device-token",),
            )
            device_count = int(cur.fetchone()["count"])
            cur.execute(
                "SELECT COUNT(*) AS count FROM notification_events WHERE event_key LIKE 'manual-smoke:%'",
            )
            notification_count = int(cur.fetchone()["count"])

    assert first.device_registration_id == second.device_registration_id
    assert first.notification_event_id == second.notification_event_id
    assert device_count == 1
    assert notification_count == 1
