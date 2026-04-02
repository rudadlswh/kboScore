from __future__ import annotations

from datetime import date

from collector.services.kbo_scoreboard_source import KBOScoreboardSource, LiveScoreSourceRequest
from tests.helpers.job_runner import build_live_source


def test_provider_phase_text_inning_maps_to_live_status():
    source = build_live_source(
        scoreboard_html_fixture="live/scoreboard_html_empty.html",
        ajax_fixture="live/scoreboard_ajax_live_phase_text.json",
    )

    states = source.fetch_live_game_states(LiveScoreSourceRequest(game_date=date(2026, 3, 28)))

    assert len(states) == 1
    assert states[0].status == "live"
    assert states[0].inning_label == "1회초"


def test_status_mapping_regression_for_scheduled_postponed_finished():
    assert (
        KBOScoreboardSource._map_status(  # noqa: SLF001 - targeted regression coverage for mapping behavior
            cancel_code="0",
            cancel_reason="정상경기",
            game_state="0",
            game_result=0,
            phase_text="경기 예정",
            inning_number=None,
            home_score=0,
            away_score=0,
        )
        == "scheduled"
    )
    assert (
        KBOScoreboardSource._map_status(  # noqa: SLF001 - targeted regression coverage for mapping behavior
            cancel_code="1",
            cancel_reason="우천취소",
            game_state="0",
            game_result=0,
            phase_text="우천취소",
            inning_number=None,
            home_score=0,
            away_score=0,
        )
        == "postponed"
    )
    assert (
        KBOScoreboardSource._map_status(  # noqa: SLF001 - targeted regression coverage for mapping behavior
            cancel_code="0",
            cancel_reason="정상경기",
            game_state="3",
            game_result=1,
            phase_text="경기 종료",
            inning_number=9,
            home_score=3,
            away_score=7,
        )
        == "finished"
    )


def test_live_source_extracts_structured_regular_season_classification():
    source = build_live_source(
        scoreboard_html_fixture="live/scoreboard_html_empty.html",
        ajax_fixture="live/scoreboard_ajax_live.json",
    )

    states = source.fetch_live_game_states(LiveScoreSourceRequest(game_date=date(2026, 3, 27)))

    assert len(states) == 1
    assert states[0].season_classification.value == "regular_season"
