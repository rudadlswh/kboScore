from __future__ import annotations

from app.services.postseason_qualification_probability_service import (
    PostseasonProbabilityUnavailableReason,
    PostseasonQualificationProbabilityService,
)
from app.services.regular_season_ranking_service import RegularSeasonRankingService
from app.services.regular_season_record_service import RegularSeasonRecordService


def make_service(simulation_count: int = 400) -> PostseasonQualificationProbabilityService:
    return PostseasonQualificationProbabilityService(
        record_service=RegularSeasonRecordService(),
        ranking_service=RegularSeasonRankingService(),
        simulation_count=simulation_count,
    )


def test_probability_returns_unavailable_when_unknown_classification_games_exist():
    service = make_service()

    summary = service.calculate_probabilities(
        team_ids=["LG", "DOO"],
        games=[
            {
                "game_id": "unknown-1",
                "home_team_id": "LG",
                "away_team_id": "DOO",
                "season_classification": "unknown",
                "status": "scheduled",
                "home_score": None,
                "away_score": None,
                "is_cancelled": False,
            }
        ],
        previous_regular_season_rank_by_team_id={"LG": 1, "DOO": 9},
    )

    assert summary.simulation_count == 0
    assert summary.probabilities_by_team_id["LG"].probability is None
    assert (
        summary.probabilities_by_team_id["LG"].unavailable_reason
        == PostseasonProbabilityUnavailableReason.UNKNOWN_CLASSIFICATION_GAMES
    )


def test_probability_returns_unavailable_when_schedule_does_not_cover_remaining_144_game_target():
    service = make_service()

    summary = service.calculate_probabilities(
        team_ids=["LG", "DOO"],
        games=[
            {
                "game_id": "final-1",
                "home_team_id": "LG",
                "away_team_id": "DOO",
                "season_classification": "regular_season",
                "status": "finished",
                "home_score": 5,
                "away_score": 2,
                "is_cancelled": False,
            }
        ],
        previous_regular_season_rank_by_team_id={"LG": 1, "DOO": 9},
    )

    assert summary.simulation_count == 0
    assert (
        summary.probabilities_by_team_id["LG"].unavailable_reason
        == PostseasonProbabilityUnavailableReason.INCOMPLETE_REGULAR_SEASON_SCHEDULE
    )


def test_probability_uses_only_regular_season_games_and_returns_probabilities_when_schedule_is_complete():
    service = make_service(simulation_count=200)
    team_ids = ["LG", "DOO"]
    games = [
        {
            "game_id": "regular-final-1",
            "home_team_id": "LG",
            "away_team_id": "DOO",
            "season_classification": "regular_season",
            "status": "finished",
            "home_score": 6,
            "away_score": 3,
            "is_cancelled": False,
        },
        {
            "game_id": "preseason-final-1",
            "home_team_id": "LG",
            "away_team_id": "DOO",
            "season_classification": "exhibition_preseason",
            "status": "finished",
            "home_score": 1,
            "away_score": 9,
            "is_cancelled": False,
        },
    ]
    for index in range(143):
        games.append(
            {
                "game_id": f"remaining-{index}",
                "home_team_id": "DOO" if index % 2 == 0 else "LG",
                "away_team_id": "LG" if index % 2 == 0 else "DOO",
                "season_classification": "regular_season",
                "status": "scheduled",
                "home_score": None,
                "away_score": None,
                "is_cancelled": False,
            }
        )

    summary = service.calculate_probabilities(
        team_ids=team_ids,
        games=games,
        previous_regular_season_rank_by_team_id={"LG": 1, "DOO": 9},
    )

    assert summary.simulation_count == 200
    assert summary.probabilities_by_team_id["LG"].probability == 1.0
    assert summary.probabilities_by_team_id["DOO"].probability == 1.0


def test_probability_output_is_stable_for_same_inputs():
    service = make_service(simulation_count=300)
    team_ids = ["LG", "DOO"]
    games = [
        {
            "game_id": "regular-final-1",
            "home_team_id": "LG",
            "away_team_id": "DOO",
            "season_classification": "regular_season",
            "status": "finished",
            "home_score": 5,
            "away_score": 2,
            "is_cancelled": False,
        }
    ]
    for index in range(143):
        games.append(
            {
                "game_id": f"stable-{index}",
                "home_team_id": "LG" if index % 2 == 0 else "DOO",
                "away_team_id": "DOO" if index % 2 == 0 else "LG",
                "season_classification": "regular_season",
                "status": "scheduled",
                "home_score": None,
                "away_score": None,
                "is_cancelled": False,
            }
        )

    first_summary = service.calculate_probabilities(
        team_ids=team_ids,
        games=games,
        previous_regular_season_rank_by_team_id={"LG": 1, "DOO": 9},
    )
    second_summary = service.calculate_probabilities(
        team_ids=team_ids,
        games=games,
        previous_regular_season_rank_by_team_id={"LG": 1, "DOO": 9},
    )

    assert (
        first_summary.probabilities_by_team_id["LG"].probability
        == second_summary.probabilities_by_team_id["LG"].probability
    )
