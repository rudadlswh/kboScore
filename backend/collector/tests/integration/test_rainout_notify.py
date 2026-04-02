from __future__ import annotations

from datetime import date, datetime

from collector.services.game_event_service import GameEventService
from collector.utils.time import KST
from tests.helpers.db_seed import (
    fetch_notification_events_for_game,
    insert_device_registration,
    insert_game,
    seed_default_teams,
)
from tests.helpers.job_runner import run_confirmed_rainout_notify_job


def test_postponed_confirmed_event_emits_notifications_once(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 27, 16, 0, tzinfo=KST)
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260327KTLG0",
            official_provider_game_id="20260327KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 27),
            scheduled_at=datetime(2026, 3, 27, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="postponed",
            is_postponed=True,
            is_cancelled=False,
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="postponed_confirmed",
            confirmed=True,
            reason="rain",
            source="weather_official_status",
            recorded_at=now_at,
            payload_json={"official_game_sc": "4"},
        )
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])
        conn.commit()

    summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        events = fetch_notification_events_for_game(conn, game_id)

    assert summary.candidate_events == 1
    assert summary.target_devices == 2
    assert summary.inserted_notification_events == 2
    assert len(events) == 2
    assert {event["delivery_status"] for event in events} == {"queued"}
    assert {event["event_type"] for event in events} == {"postponed_confirmed"}
    assert {event["title"] for event in events} == {"경기 우천 취소"}


def test_notification_generator_is_idempotent_for_repeated_runs(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 27, 16, 0, tzinfo=KST)
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260327KTLG0",
            official_provider_game_id="20260327KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 27),
            scheduled_at=datetime(2026, 3, 27, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="postponed",
            is_postponed=True,
            is_cancelled=False,
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="postponed_confirmed",
            confirmed=True,
            reason="rain",
            source="weather_official_status",
            recorded_at=now_at,
            payload_json={"official_game_sc": "4"},
        )
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])
        conn.commit()

    first_summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )
    second_summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        events = fetch_notification_events_for_game(conn, game_id)

    assert len(events) == 2
    assert first_summary.inserted_notification_events == 2
    assert second_summary.inserted_notification_events == 0
    assert second_summary.skipped_duplicates == 2


def test_favorite_team_targeting_matches_only_home_and_away_devices(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 11, 0, tzinfo=KST)
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
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="time_changed",
            confirmed=True,
            reason=None,
            source="schedule_bootstrap",
            recorded_at=now_at,
            payload_json={
                "old_scheduled_at": "2026-03-28T18:30:00+09:00",
                "new_scheduled_at": "2026-03-28T19:00:00+09:00",
            },
        )
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])
        insert_device_registration(conn, device_token="token-other", favorite_team_id=team_ids["DOOSAN"])
        insert_device_registration(conn, device_token="token-null", favorite_team_id=None)
        insert_device_registration(conn, device_token="token-disabled", favorite_team_id=team_ids["LG"], notifications_enabled=False)
        conn.commit()

    summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        events = fetch_notification_events_for_game(conn, game_id)

    assert summary.target_devices == 2
    assert summary.inserted_notification_events == 2
    assert len(events) == 2


def test_non_notifiable_status_corrected_event_does_not_emit_notifications(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 12, 0, tzinfo=KST)
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
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="status_corrected",
            confirmed=True,
            reason=None,
            source="schedule_bootstrap",
            recorded_at=now_at,
            payload_json={"old_status": "unknown", "new_status": "scheduled"},
        )
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        conn.commit()

    summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        events = fetch_notification_events_for_game(conn, game_id)

    assert summary.candidate_events == 0
    assert summary.inserted_notification_events == 0
    assert events == []


def test_time_changed_event_emits_notification_with_semantic_detail(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 10, 30, tzinfo=KST)
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 19, 0, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="time_changed",
            confirmed=True,
            reason=None,
            source="schedule_bootstrap",
            recorded_at=now_at,
            payload_json={
                "old_scheduled_at": "2026-03-28T18:30:00+09:00",
                "new_scheduled_at": "2026-03-28T19:00:00+09:00",
            },
        )
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        conn.commit()

    run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        event = fetch_notification_events_for_game(conn, game_id)[0]

    assert event["event_type"] == "time_changed"
    assert event["title"] == "경기 시간 변경"
    assert "18:30" in event["body"]
    assert "19:00" in event["body"]
    assert event["payload_json"]["event_payload"]["old_scheduled_at"] == "2026-03-28T18:30:00+09:00"
    assert event["payload_json"]["event_payload"]["new_scheduled_at"] == "2026-03-28T19:00:00+09:00"


def test_venue_changed_event_emits_notification_with_semantic_detail(db_connection_factory, test_logger):
    now_at = datetime(2026, 3, 28, 10, 30, tzinfo=KST)
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328KTLG0",
            official_provider_game_id="20260328KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="고척",
            stadium_code="GC",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
            source_updated_at=now_at,
        )
        GameEventService(conn).record_event(
            game_id=game_id,
            event_type="venue_changed",
            confirmed=True,
            reason=None,
            source="schedule_bootstrap",
            recorded_at=now_at,
            payload_json={
                "old_stadium": "잠실",
                "new_stadium": "고척",
                "old_stadium_code": "JS",
                "new_stadium_code": "GC",
            },
        )
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])
        conn.commit()

    run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        event = fetch_notification_events_for_game(conn, game_id)[0]

    assert event["event_type"] == "venue_changed"
    assert event["title"] == "경기 장소 변경"
    assert "잠실" in event["body"]
    assert "고척" in event["body"]
    assert event["payload_json"]["event_payload"]["old_stadium"] == "잠실"
    assert event["payload_json"]["event_payload"]["new_stadium"] == "고척"
