from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime

import pytest

from collector.config import CollectorConfig
from collector.manual_notification_smoke import build_sandbox_apns_client, run_manual_notification_smoke_test
from collector.services.apns_client import APNSConfigurationError, APNSNotificationRequest
from collector.services.notification_delivery_service import NotificationDeliverySummary
from collector.utils.time import KST
from tests.helpers.db_seed import (
    fetch_notification_event_by_id,
    insert_device_registration,
    insert_game,
    insert_notification_event,
    seed_default_teams,
)


@dataclass(slots=True)
class FakeAPNSClient:
    sent_requests: list[APNSNotificationRequest] = field(default_factory=list)

    def send_notification(self, request: APNSNotificationRequest) -> None:
        self.sent_requests.append(request)


def _build_config(**overrides) -> CollectorConfig:
    values = {
        "database_url": "postgresql://admin:adminkbo@127.0.0.1:55432/kbo",
        "notification_delivery_enabled": False,
        "notification_delivery_interval_seconds": 30,
        "notification_delivery_batch_size": 100,
        "notification_delivery_max_attempts": 3,
        "notification_retry_delays_seconds": (60, 300),
        "apns_team_id": "TEAM123",
        "apns_key_id": "KEY123",
        "apns_bundle_id": "com.kbo.score",
        "apns_private_key_path": "/tmp/AuthKey_KEY123.p8",
        "apns_use_sandbox": True,
    }
    values.update(overrides)
    return CollectorConfig(**values)


def _seed_smoke_target(db_connection_factory):
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
        )
        first_device_id = insert_device_registration(
            conn,
            device_token="smoke-token-1",
            favorite_team_id=team_ids["LG"],
            notifications_enabled=True,
        )
        second_device_id = insert_device_registration(
            conn,
            device_token="smoke-token-2",
            favorite_team_id=team_ids["LG"],
            notifications_enabled=True,
        )
        first_event_id = insert_notification_event(
            conn,
            device_registration_id=first_device_id,
            game_id=game_id,
            event_type="postponed_confirmed",
            event_key="smoke-event-1",
            title="경기 우천 취소",
            body="KT vs LG 경기가 우천으로 취소되었습니다.",
        )
        second_event_id = insert_notification_event(
            conn,
            device_registration_id=second_device_id,
            game_id=game_id,
            event_type="time_changed",
            event_key="smoke-event-2",
            title="경기 시간 변경",
            body="KT vs LG 경기 시간이 변경되었습니다.",
        )
    return first_event_id, second_event_id


def test_manual_smoke_test_refuses_when_sandbox_config_is_incomplete():
    with pytest.raises(APNSConfigurationError):
        build_sandbox_apns_client(
            _build_config(
                apns_team_id=None,
                apns_key_id=None,
                apns_bundle_id=None,
                apns_private_key_path=None,
            )
        )

    with pytest.raises(APNSConfigurationError):
        build_sandbox_apns_client(_build_config(apns_use_sandbox=False))


def test_manual_smoke_test_scopes_itself_to_one_explicit_queued_row(db_connection_factory, test_logger):
    first_event_id, second_event_id = _seed_smoke_target(db_connection_factory)
    client = FakeAPNSClient()

    summary = run_manual_notification_smoke_test(
        notification_event_id=first_event_id,
        config=_build_config(),
        logger=test_logger,
        now_at=datetime(2026, 3, 28, 16, 0, tzinfo=KST),
        db_connection_factory=db_connection_factory,
        apns_client=client,
    )

    with db_connection_factory() as conn:
        first_row = fetch_notification_event_by_id(conn, first_event_id)
        second_row = fetch_notification_event_by_id(conn, second_event_id)

    assert summary.selected_rows == 1
    assert summary.sent_rows == 1
    assert len(client.sent_requests) == 1
    assert client.sent_requests[0].device_token == "smoke-token-1"
    assert first_row is not None
    assert first_row["delivery_status"] == "sent"
    assert second_row is not None
    assert second_row["delivery_status"] == "queued"


def test_manual_smoke_test_uses_existing_delivery_service(monkeypatch, test_logger):
    observed_at = datetime(2026, 3, 28, 16, 0, tzinfo=KST)
    captured = {}

    class FakeConnection:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def commit(self):
            captured["committed"] = True

    class FakeService:
        def __init__(self, conn, apns_client):
            captured["conn"] = conn
            captured["apns_client"] = apns_client

        def deliver_notification_event_by_id(self, *, notification_event_id, observed_at, max_attempts, retry_delays_seconds):
            captured["notification_event_id"] = notification_event_id
            captured["observed_at"] = observed_at
            captured["max_attempts"] = max_attempts
            captured["retry_delays_seconds"] = retry_delays_seconds
            return NotificationDeliverySummary(selected_rows=1, attempted_rows=1, sent_rows=1, failed_rows=0)

    monkeypatch.setattr("collector.manual_notification_smoke.NotificationDeliveryService", FakeService)

    summary = run_manual_notification_smoke_test(
        notification_event_id="00000000-0000-0000-0000-000000000001",
        config=_build_config(notification_delivery_max_attempts=4, notification_retry_delays_seconds=(30, 120)),
        logger=test_logger,
        now_at=observed_at,
        db_connection_factory=lambda: FakeConnection(),
        apns_client=FakeAPNSClient(),
    )

    assert summary.sent_rows == 1
    assert captured["notification_event_id"] == "00000000-0000-0000-0000-000000000001"
    assert captured["observed_at"] == observed_at
    assert captured["max_attempts"] == 4
    assert captured["retry_delays_seconds"] == (30, 120)
    assert captured["committed"] is True
