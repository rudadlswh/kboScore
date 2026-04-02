from __future__ import annotations

from datetime import date, datetime

from collector.utils.time import KST
from tests.helpers.db_seed import (
    fetch_game_by_id,
    fetch_game_snapshots_for_game,
    insert_game,
    seed_default_teams,
)
from tests.helpers.job_runner import build_live_source, run_live_poll_job


def test_live_first_insert(db_connection_factory, test_logger):
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
            status="scheduled",
        )

    summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_live.json",
        ),
        now_at=datetime(2026, 3, 27, 18, 20, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        snapshots = fetch_game_snapshots_for_game(conn, game_id)
        assert len(snapshots) == 1

    assert summary.candidate_games == 1
    assert summary.inserted_snapshots == 1


def test_live_unchanged_skip(db_connection_factory, test_logger):
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
            status="scheduled",
        )

    first_summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_live.json",
        ),
        now_at=datetime(2026, 3, 27, 18, 20, tzinfo=KST),
    )
    second_summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_live.json",
        ),
        now_at=datetime(2026, 3, 27, 18, 21, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        snapshots = fetch_game_snapshots_for_game(conn, game_id)
        assert len(snapshots) == 1

    assert first_summary.inserted_snapshots == 1
    assert second_summary.skipped_unchanged == 1


def test_scheduled_to_live_transition(db_connection_factory, test_logger):
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
            status="scheduled",
        )

    summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_live.json",
        ),
        now_at=datetime(2026, 3, 27, 18, 20, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_id(conn, game_id)
        assert game is not None
        assert game["status"] == "live"
        assert game["inning_state"] == "7회초"
        assert game["home_score"] == 2
        assert game["away_score"] == 3
        assert game["season_classification"] == "regular_season"

    assert summary.canonical_updates == 1


def test_live_to_finished_transition(db_connection_factory, test_logger):
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
            status="live",
            home_score=2,
            away_score=3,
            inning_state="7회초",
        )

    summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_finished.json",
        ),
        now_at=datetime(2026, 3, 27, 21, 30, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_id(conn, game_id)
        assert game is not None
        assert game["status"] == "finished"
        assert game["inning_state"] == "9회말"
        assert game["home_score"] == 3
        assert game["away_score"] == 7
        assert game["season_classification"] == "regular_season"

    assert summary.canonical_updates == 1


def test_phase_text_inning_promotes_scheduled_to_live(db_connection_factory, test_logger):
    with db_connection_factory() as conn:
        team_ids = seed_default_teams(conn)
        game_id = insert_game(
            conn,
            provider_game_id="20260328LGDOO0",
            official_provider_game_id="20260328LGDOO0",
            provider_game_id_kind="official",
            game_date=date(2026, 3, 28),
            scheduled_at=datetime(2026, 3, 28, 18, 30, tzinfo=KST),
            stadium="잠실",
            stadium_code="JS",
            home_team_id=team_ids["DOOSAN"],
            away_team_id=team_ids["LG"],
            status="scheduled",
        )

    summary = run_live_poll_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        live_source=build_live_source(
            scoreboard_html_fixture="live/scoreboard_html_empty.html",
            ajax_fixture="live/scoreboard_ajax_live_phase_text.json",
        ),
        now_at=datetime(2026, 3, 28, 18, 40, tzinfo=KST),
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_id(conn, game_id)
        assert game is not None
        assert game["status"] == "live"
        assert game["inning_state"] == "1회초"

    assert summary.inserted_snapshots == 1
    assert summary.canonical_updates == 1
