from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

import pytest

from collector.app import CollectorRuntimeState, build_runtime_state, run_runtime_tick
from collector.config import CollectorConfig
from collector.jobs.notification_delivery_job import NotificationDeliveryJobSummary
from collector.services.apns_client import APNSConfigurationError
from collector.utils.time import KST


def _build_config(**overrides) -> CollectorConfig:
    values = {
        "database_url": "postgresql://admin:adminkbo@127.0.0.1:55432/kbo",
        "live_poll_enabled": False,
        "notification_delivery_enabled": False,
        "notification_delivery_interval_seconds": 30,
        "notification_delivery_batch_size": 100,
        "notification_delivery_max_attempts": 3,
        "notification_retry_delays_seconds": (60, 300),
        "apns_team_id": "TEAM123",
        "apns_key_id": "KEY123",
        "apns_bundle_id": "com.kbo.score",
        "apns_private_key_path": "/tmp/AuthKey_KEY123.p8",
    }
    values.update(overrides)
    return CollectorConfig(**values)


def test_build_runtime_state_registers_delivery_job_when_enabled(monkeypatch, test_logger):
    fake_client = object()
    captured = {}

    class FakeNotificationDeliveryJob:
        job_name = "notification_delivery_job"

        def __init__(self, deps):
            captured["deps"] = deps

    monkeypatch.setattr(
        "collector.app.TokenBasedAPNSClient.from_config",
        classmethod(lambda cls, config: fake_client),
    )
    monkeypatch.setattr("collector.app.NotificationDeliveryJob", FakeNotificationDeliveryJob)

    state = build_runtime_state(
        config=_build_config(notification_delivery_enabled=True),
        logger=test_logger,
        db_connection_factory=lambda: object(),
    )

    assert state.notification_delivery_job is not None
    assert isinstance(state.notification_delivery_job, FakeNotificationDeliveryJob)
    assert state.next_notification_delivery_at is not None
    assert captured["deps"].apns_client is fake_client


def test_build_runtime_state_does_not_register_or_run_when_disabled(monkeypatch, test_logger):
    monkeypatch.setattr(
        "collector.app.TokenBasedAPNSClient.from_config",
        classmethod(lambda cls, config: pytest.fail("APNs config should not be loaded when delivery is disabled")),
    )
    state = build_runtime_state(config=_build_config(notification_delivery_enabled=False), logger=test_logger)

    result = run_runtime_tick(
        state=state,
        config=_build_config(notification_delivery_enabled=False),
        logger=test_logger,
        now_at=datetime(2026, 3, 28, 12, 0, tzinfo=KST),
    )

    assert state.notification_delivery_job is None
    assert result is None


def test_missing_apns_config_fails_only_when_delivery_enabled(test_logger):
    enabled_config = _build_config(
        notification_delivery_enabled=True,
        apns_team_id=None,
        apns_key_id=None,
        apns_bundle_id=None,
        apns_private_key_path=None,
    )
    disabled_config = _build_config(
        notification_delivery_enabled=False,
        apns_team_id=None,
        apns_key_id=None,
        apns_bundle_id=None,
        apns_private_key_path=None,
    )

    with pytest.raises(APNSConfigurationError):
        build_runtime_state(config=enabled_config, logger=test_logger)

    state = build_runtime_state(config=disabled_config, logger=test_logger)
    assert state.notification_delivery_job is None


def test_run_runtime_tick_invokes_existing_delivery_job_without_changing_semantics(test_logger):
    observed_at = datetime(2026, 3, 28, 12, 0, tzinfo=KST)
    captured = {}

    @dataclass
    class FakeNotificationDeliveryJob:
        job_name: str = "notification_delivery_job"

        def execute(self, request):
            captured["request"] = request
            return NotificationDeliveryJobSummary(
                selected_rows=3,
                attempted_rows=2,
                sent_rows=1,
                failed_rows=1,
            )

    state = CollectorRuntimeState(
        notification_delivery_job=FakeNotificationDeliveryJob(),
        next_notification_delivery_at=observed_at - timedelta(seconds=1),
    )
    config = _build_config(
        notification_delivery_enabled=True,
        notification_delivery_interval_seconds=45,
        notification_delivery_batch_size=25,
        notification_delivery_max_attempts=4,
        notification_retry_delays_seconds=(10, 60, 300),
    )

    summary = run_runtime_tick(state=state, config=config, logger=test_logger, now_at=observed_at)

    assert summary is not None
    assert summary.selected_rows == 3
    assert summary.sent_rows == 1
    assert captured["request"].now_at == observed_at
    assert captured["request"].batch_size == 25
    assert captured["request"].max_attempts == 4
    assert captured["request"].retry_delays_seconds == (10, 60, 300)
    assert state.next_notification_delivery_at == observed_at + timedelta(seconds=45)


def test_run_runtime_tick_invokes_live_poll_job_when_enabled(test_logger):
    observed_at = datetime(2026, 3, 28, 12, 0, tzinfo=KST)
    captured = {}

    @dataclass
    class FakeLiveScorePollJobSummary:
        candidate_games: int = 1
        polled_games: int = 1
        inserted_snapshots: int = 1
        skipped_unchanged: int = 0
        canonical_updates: int = 1
        parse_failures: int = 0

    @dataclass
    class FakeLiveScorePollJob:
        job_name: str = "live_score_poll_job"

        def run_with_retry(self, request):
            captured["request"] = request
            return FakeLiveScorePollJobSummary()

    state = CollectorRuntimeState(
        live_score_poll_job=FakeLiveScorePollJob(),
        next_live_score_poll_at=observed_at - timedelta(seconds=1),
    )
    config = _build_config(
        live_poll_enabled=True,
        live_poll_interval_seconds=12,
        notification_delivery_enabled=False,
    )

    summary = run_runtime_tick(state=state, config=config, logger=test_logger, now_at=observed_at)

    assert summary is None
    assert captured["request"].now_at == observed_at
    assert state.next_live_score_poll_at == observed_at + timedelta(seconds=12)
