from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from collector.services.apns_client import APNSDeliveryError, APNSNotificationRequest
from collector.utils.time import KST
from tests.helpers.db_seed import (
    delete_device_registration,
    fetch_device_registration_by_id,
    fetch_notification_event_by_id,
    insert_device_registration,
    insert_game,
    insert_notification_event,
    seed_default_teams,
)
from tests.helpers.job_runner import run_notification_delivery_job


@dataclass(slots=True)
class FakeAPNSClient:
    sent_requests: list[APNSNotificationRequest] = field(default_factory=list)
    failure_by_token: dict[str, APNSDeliveryError] = field(default_factory=dict)

    def send_notification(self, request: APNSNotificationRequest) -> None:
        error = self.failure_by_token.get(request.device_token)
        if error is not None:
            raise error
        self.sent_requests.append(request)


def _seed_delivery_target(db_connection_factory, *, device_token: str = "token-home", notifications_enabled: bool = True):
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
        device_id = insert_device_registration(
            conn,
            device_token=device_token,
            favorite_team_id=team_ids["LG"],
            notifications_enabled=notifications_enabled,
        )
    return game_id, device_id


def test_retryable_apns_failure_is_retried_and_can_eventually_be_sent(db_connection_factory, test_logger):
    first_now = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    second_now = first_now + timedelta(seconds=61)
    game_id, device_id = _seed_delivery_target(db_connection_factory)

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="postponed_confirmed",
            event_key="retry-then-send",
            title="경기 우천 취소",
            body="KT vs LG 경기가 우천으로 취소되었습니다.",
        )

    first_client = FakeAPNSClient(
        failure_by_token={
            "token-home": APNSDeliveryError("apns_timeout", retryable=True),
        }
    )
    first_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=first_client,
        now_at=first_now,
        retry_delays_seconds=(60, 300),
    )

    with db_connection_factory() as conn:
        after_first = fetch_notification_event_by_id(conn, notification_event_id)

    second_client = FakeAPNSClient()
    second_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=second_client,
        now_at=second_now,
        retry_delays_seconds=(60, 300),
    )

    with db_connection_factory() as conn:
        after_second = fetch_notification_event_by_id(conn, notification_event_id)

    assert first_summary.failed_rows == 1
    assert after_first is not None
    assert after_first["delivery_status"] == "failed"
    assert after_first["attempt_count"] == 1
    assert after_first["next_attempt_at"] == first_now + timedelta(seconds=60)
    assert second_summary.sent_rows == 1
    assert len(second_client.sent_requests) == 1
    assert after_second is not None
    assert after_second["delivery_status"] == "sent"
    assert after_second["attempt_count"] == 2
    assert after_second["next_attempt_at"] is None


def test_terminal_failures_are_not_retried(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    later_now = now_at + timedelta(hours=1)
    game_id, device_id = _seed_delivery_target(db_connection_factory, device_token="bad-token")

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="venue_changed",
            event_key="terminal-failure",
            title="경기 장소 변경",
            body="경기 장소가 변경되었습니다.",
        )

    first_client = FakeAPNSClient(
        failure_by_token={
            "bad-token": APNSDeliveryError("BadDeviceToken", retryable=False, disable_device=True),
        }
    )
    first_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=first_client,
        now_at=now_at,
    )
    second_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=FakeAPNSClient(),
        now_at=later_now,
    )

    with db_connection_factory() as conn:
        row = fetch_notification_event_by_id(conn, notification_event_id)
        device = fetch_device_registration_by_id(conn, device_id)

    assert first_summary.failed_rows == 1
    assert second_summary.selected_rows == 0
    assert row is not None
    assert row["delivery_status"] == "failed"
    assert row["next_attempt_at"] is None
    assert row["failure_reason"] == "BadDeviceToken"
    assert device is not None
    assert device["notifications_enabled"] is False


def test_max_attempt_behavior_stops_further_retries(db_connection_factory, test_logger):
    first_now = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    second_now = first_now + timedelta(seconds=61)
    third_now = second_now + timedelta(seconds=301)
    game_id, device_id = _seed_delivery_target(db_connection_factory)

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="time_changed",
            event_key="max-attempts",
            title="경기 시간 변경",
            body="경기 시간이 변경되었습니다.",
        )

    failure = APNSDeliveryError("apns_http_500", retryable=True)
    client = FakeAPNSClient(failure_by_token={"token-home": failure})

    first_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=client,
        now_at=first_now,
        max_attempts=2,
        retry_delays_seconds=(60, 300),
    )
    second_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=client,
        now_at=second_now,
        max_attempts=2,
        retry_delays_seconds=(60, 300),
    )
    third_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=client,
        now_at=third_now,
        max_attempts=2,
        retry_delays_seconds=(60, 300),
    )

    with db_connection_factory() as conn:
        row = fetch_notification_event_by_id(conn, notification_event_id)

    assert first_summary.failed_rows == 1
    assert second_summary.failed_rows == 1
    assert third_summary.selected_rows == 0
    assert row is not None
    assert row["attempt_count"] == 2
    assert row["next_attempt_at"] is None


def test_invalid_token_failure_disables_device_registration(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    game_id, device_id = _seed_delivery_target(db_connection_factory, device_token="unregistered-token")

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="postponed_confirmed",
            event_key="disable-invalid-token",
            title="경기 우천 취소",
            body="경기가 취소되었습니다.",
        )

    client = FakeAPNSClient(
        failure_by_token={
            "unregistered-token": APNSDeliveryError("Unregistered", retryable=False, disable_device=True),
        }
    )
    run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=client,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        row = fetch_notification_event_by_id(conn, notification_event_id)
        device = fetch_device_registration_by_id(conn, device_id)

    assert row is not None
    assert row["delivery_status"] == "failed"
    assert row["failure_reason"] == "Unregistered"
    assert device is not None
    assert device["notifications_enabled"] is False


def test_already_sent_rows_are_never_retried(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    game_id, device_id = _seed_delivery_target(db_connection_factory)

    with db_connection_factory() as conn:
        insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="time_changed",
            event_key="already-sent",
            title="경기 시간 변경",
            body="경기 시간이 변경되었습니다.",
            delivery_status="sent",
            attempt_count=1,
        )

    summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=FakeAPNSClient(),
        now_at=now_at,
    )

    assert summary.selected_rows == 0
    assert summary.sent_rows == 0


def test_backoff_logic_prevents_immediate_hot_loop_retry(db_connection_factory, test_logger):
    first_now = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    early_now = first_now + timedelta(seconds=30)
    game_id, device_id = _seed_delivery_target(db_connection_factory)

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="venue_changed",
            event_key="hot-loop-block",
            title="경기 장소 변경",
            body="경기 장소가 변경되었습니다.",
        )

    failing_client = FakeAPNSClient(
        failure_by_token={"token-home": APNSDeliveryError("apns_transport_error", retryable=True)}
    )
    run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=failing_client,
        now_at=first_now,
        retry_delays_seconds=(60, 300),
    )
    early_summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=FakeAPNSClient(),
        now_at=early_now,
        retry_delays_seconds=(60, 300),
    )

    with db_connection_factory() as conn:
        row = fetch_notification_event_by_id(conn, notification_event_id)

    assert early_summary.selected_rows == 0
    assert row is not None
    assert row["next_attempt_at"] == first_now + timedelta(seconds=60)
    assert row["delivery_status"] == "failed"


def test_batch_limits_work_with_mixed_queued_and_retryable_rows(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    retry_due = now_at - timedelta(seconds=1)
    game_id, first_device_id = _seed_delivery_target(db_connection_factory, device_token="token-1")

    with db_connection_factory() as conn:
        second_device_id = insert_device_registration(conn, device_token="token-2", favorite_team_id=None)
        first_event_id = insert_notification_event(
            conn,
            device_registration_id=first_device_id,
            game_id=game_id,
            event_type="time_changed",
            event_key="mixed-retryable",
            title="경기 시간 변경",
            body="retry row",
            delivery_status="failed",
            attempt_count=1,
            next_attempt_at=retry_due,
            failure_reason="apns_timeout",
        )
        second_event_id = insert_notification_event(
            conn,
            device_registration_id=second_device_id,
            game_id=game_id,
            event_type="venue_changed",
            event_key="mixed-queued",
            title="경기 장소 변경",
            body="queued row",
            delivery_status="queued",
            created_at=now_at,
        )
        conn.commit()

    summary = run_notification_delivery_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        apns_client=FakeAPNSClient(),
        now_at=now_at,
        batch_size=1,
        retry_delays_seconds=(60, 300),
    )

    with db_connection_factory() as conn:
        first_row = fetch_notification_event_by_id(conn, first_event_id)
        second_row = fetch_notification_event_by_id(conn, second_event_id)

    assert summary.selected_rows == 1
    assert summary.sent_rows == 1
    assert first_row is not None and first_row["delivery_status"] == "sent"
    assert second_row is not None and second_row["delivery_status"] == "queued"


def test_terminal_debug_query_logic_works(db_connection_factory):
    now_at = datetime(2026, 3, 28, 15, 0, tzinfo=KST)
    game_id, device_id = _seed_delivery_target(db_connection_factory)

    with db_connection_factory() as conn:
        notification_event_id = insert_notification_event(
            conn,
            device_registration_id=device_id,
            game_id=game_id,
            event_type="postponed_confirmed",
            event_key="debug-query",
            title="경기 우천 취소",
            body="경기가 취소되었습니다.",
            delivery_status="failed",
            attempt_count=2,
            failure_reason="Unregistered",
            created_at=now_at,
        )
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id::text AS id,
                    event_key,
                    delivery_status,
                    attempt_count,
                    attempted_at,
                    sent_at,
                    failed_at,
                    failure_reason,
                    device_registration_id::text AS device_registration_id,
                    game_id::text AS game_id
                FROM notification_events
                WHERE delivery_status = %s
                  AND created_at::date = %s
                ORDER BY created_at ASC, id ASC
                """,
                ("failed", now_at.date()),
            )
            rows = list(cur.fetchall())

    assert rows == [
        {
            "id": notification_event_id,
            "event_key": "debug-query",
            "delivery_status": "failed",
            "attempt_count": 2,
            "attempted_at": None,
            "sent_at": None,
            "failed_at": None,
            "failure_reason": "Unregistered",
            "device_registration_id": device_id,
            "game_id": game_id,
        }
    ]
