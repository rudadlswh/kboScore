from __future__ import annotations

from tests.helpers.db_seed import count_rows, fetch_game_by_provider_game_id, seed_default_teams
from tests.helpers.job_runner import build_live_source, build_schedule_source, run_schedule_bootstrap_job


def test_bootstrap_first_run(db_connection_factory, test_logger, caplog):
    with db_connection_factory() as conn:
        seed_default_teams(conn)

    schedule_source = build_schedule_source(primary_fixture="schedule/schedule_ajax_2026_03.json")
    summary = run_schedule_bootstrap_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        schedule_source=schedule_source,
        season_id=2026,
        months=[3],
    )

    with db_connection_factory() as conn:
        assert count_rows(conn, "games") == 1
        game = fetch_game_by_provider_game_id(conn, "20260327KTLG0")
        assert game is not None
        assert game["official_provider_game_id"] == "20260327KTLG0"
        assert game["provider_game_id_kind"] == "official"
        assert game["provider_game_id"] == "20260327KTLG0"
        assert game["stadium_code"] == "JS"
        assert game["season_classification"] == "unknown"

    assert summary.inserted_count == 1
    assert summary.updated_count == 0
    assert summary.unresolved_team_count == 0
    assert summary.unresolved_stadium_count == 0
    assert "bootstrap_month_committed" in caplog.text


def test_bootstrap_rerun_idempotent(db_connection_factory, test_logger):
    with db_connection_factory() as conn:
        seed_default_teams(conn)

    first_source = build_schedule_source(primary_fixture="schedule/schedule_ajax_2026_03.json")
    second_source = build_schedule_source(primary_fixture="schedule/schedule_ajax_2026_03.json")

    first_summary = run_schedule_bootstrap_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        schedule_source=first_source,
        season_id=2026,
        months=[3],
    )
    second_summary = run_schedule_bootstrap_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        schedule_source=second_source,
        season_id=2026,
        months=[3],
    )

    with db_connection_factory() as conn:
        assert count_rows(conn, "games") == 1
        game = fetch_game_by_provider_game_id(conn, "20260327KTLG0")
        assert game is not None
        assert game["provider_game_id"] == "20260327KTLG0"
        assert game["official_provider_game_id"] == "20260327KTLG0"
        assert game["season_classification"] == "unknown"

    assert first_summary.inserted_count == 1
    assert second_summary.inserted_count == 0
    assert second_summary.updated_count == 0


def test_bootstrap_resolves_unknown_march_opening_row_when_scoreboard_has_explicit_classification(
    db_connection_factory,
    test_logger,
):
    with db_connection_factory() as conn:
        seed_default_teams(conn)

    schedule_source = build_schedule_source(primary_fixture="schedule/schedule_ajax_2026_03.json")
    scoreboard_source = build_live_source(
        scoreboard_html_fixture="live/scoreboard_html_empty.html",
        ajax_fixture="live/scoreboard_ajax_scheduled.json",
    )

    summary = run_schedule_bootstrap_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        schedule_source=schedule_source,
        scoreboard_source=scoreboard_source,
        season_id=2026,
        months=[3],
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_provider_game_id(conn, "20260327KTLG0")
        assert game is not None
        assert game["season_classification"] == "regular_season"

    assert summary.resolved_unknown_season_classification_count == 1
    assert summary.unresolved_season_classification_count == 0


def test_bootstrap_keeps_unknown_march_row_when_scoreboard_source_has_no_explicit_evidence(
    db_connection_factory,
    test_logger,
):
    with db_connection_factory() as conn:
        seed_default_teams(conn)

    schedule_source = build_schedule_source(primary_fixture="schedule/schedule_ajax_2026_03.json")
    scoreboard_source = build_live_source(
        scoreboard_html_fixture="live/scoreboard_html_empty.html",
        ajax_fixture=None,
    )

    summary = run_schedule_bootstrap_job(
        db_connection_factory=db_connection_factory,
        logger=test_logger,
        schedule_source=schedule_source,
        scoreboard_source=scoreboard_source,
        season_id=2026,
        months=[3],
    )

    with db_connection_factory() as conn:
        game = fetch_game_by_provider_game_id(conn, "20260327KTLG0")
        assert game is not None
        assert game["season_classification"] == "unknown"

    assert summary.resolved_unknown_season_classification_count == 0
    assert summary.unresolved_season_classification_count == 1
