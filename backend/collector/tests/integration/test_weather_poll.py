from __future__ import annotations

from datetime import date, datetime

from collector.utils.time import KST
from tests.helpers.db_seed import (
    fetch_game_by_id,
    fetch_weather_snapshots_for_game,
    insert_game,
    seed_default_teams,
)
from tests.helpers.job_runner import build_weather_source, run_weather_poll_job


def test_weather_first_insert(db_connection_factory, test_logger):
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
        )

    weather_source = build_weather_source(
        weather_fixture="weather/weather_ajax_js_clear.json",
        today_games_fixture="weather/today_games_postponed.json",
    )
    summary = run_weather_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        weather_source=weather_source,
        now_at=datetime(2026, 3, 27, 14, 0, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        snapshots = fetch_weather_snapshots_for_game(conn, game_id)
        assert len(snapshots) == 1
        assert snapshots[0]["source_name"] == "weather_ajax"
        assert snapshots[0]["content_hash"]

    assert summary.due_games == 1
    assert summary.inserted_snapshots == 1


def test_weather_unchanged_skip(db_connection_factory, test_logger):
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260327KTLG0",
            official_provider_game_id="20260327KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 27),
            scheduled_at=datetime(2026, 3, 27, 14, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
        )

    first_summary = run_weather_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        weather_source=build_weather_source(weather_fixture="weather/weather_ajax_js_unchanged.json"),
        now_at=datetime(2026, 3, 27, 14, 30, tzinfo=KST),
    )
    second_summary = run_weather_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        weather_source=build_weather_source(weather_fixture="weather/weather_ajax_js_unchanged.json"),
        now_at=datetime(2026, 3, 27, 15, 0, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        snapshots = fetch_weather_snapshots_for_game(conn, game_id)
        assert len(snapshots) == 1

    assert first_summary.inserted_snapshots == 1
    assert second_summary.skipped_unchanged == 1


def test_confirmed_postponed_update(db_connection_factory, test_logger):
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260327KTLG0",
            official_provider_game_id="20260327KTLG0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 27),
            scheduled_at=datetime(2026, 3, 27, 14, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["LG"],
            away_team_id=team_ids["KT"],
            status="scheduled",
        )

    summary = run_weather_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        weather_source=build_weather_source(
            weather_fixture="weather/weather_ajax_js_clear.json",
            today_games_fixture="weather/today_games_postponed.json",
        ),
        now_at=datetime(2026, 3, 27, 14, 30, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_id(conn, game_id)
        assert game is not None
        assert game["status"] == "postponed"
        assert game["is_postponed"] is True
        assert game["is_cancelled"] is False

    assert summary.polled_games == 1
