from __future__ import annotations

from datetime import date, datetime

from collector.utils.time import KST
from tests.helpers.db_seed import (
    fetch_notification_events_for_game,
    insert_device_registration,
    insert_game,
    seed_default_teams,
)
from tests.helpers.job_runner import run_confirmed_rainout_notify_job


def test_confirmed_rainout_notification_insert(db_connection_factory, test_logger):
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
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])
        insert_device_registration(conn, device_token="token-disabled", favorite_team_id=team_ids["LG"], notifications_enabled=False)

    summary = run_confirmed_rainout_notify_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        now_at=now_at,
    )

    with db_connection_factory() as conn:
        events = fetch_notification_events_for_game(conn, game_id)
        assert len(events) == 2
        assert {event["delivery_status"] for event in events} == {"queued"}
        assert {event["event_type"] for event in events} == {"rainout_confirmed"}

    assert summary.candidate_games == 1
    assert summary.target_devices == 2
    assert summary.inserted_notification_events == 2


def test_duplicate_notification_skip(db_connection_factory, test_logger):
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
        insert_device_registration(conn, device_token="token-home", favorite_team_id=team_ids["LG"])
        insert_device_registration(conn, device_token="token-away", favorite_team_id=team_ids["KT"])

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
