from __future__ import annotations

from app.services.regular_season_ranking_service import RankingResolution, RegularSeasonRankingService
from app.services.regular_season_record_service import TeamRegularSeasonRecord


def test_tie_for_fifth_place_requires_tiebreak_game():
    service = RegularSeasonRankingService()

    ranked = service.rank_records(
        records=[
            TeamRegularSeasonRecord("LG", 10, 5, 0, 15, 129, 0),
            TeamRegularSeasonRecord("HANWHA", 9, 6, 0, 15, 129, 0),
            TeamRegularSeasonRecord("SSG", 8, 7, 0, 15, 129, 0),
            TeamRegularSeasonRecord("SAMSUNG", 7, 8, 0, 15, 129, 0),
            TeamRegularSeasonRecord("NC", 6, 9, 0, 15, 129, 0),
            TeamRegularSeasonRecord("KT", 6, 9, 0, 15, 129, 0),
        ],
        games=[
            {
                "home_team_id": "NC",
                "away_team_id": "KT",
                "status": "finished",
                "season_classification": "regular_season",
                "home_score": 4,
                "away_score": 3,
            }
        ],
        previous_regular_season_rank_by_team_id={
            "LG": 1,
            "HANWHA": 2,
            "SSG": 3,
            "SAMSUNG": 4,
            "NC": 5,
            "KT": 6,
        },
    )

    assert ranked[4].team_id == "NC"
    assert ranked[4].ranking_resolution == RankingResolution.TIEBREAK_GAME_REQUIRED
    assert ranked[4].ranking_resolution_position == 5
    assert ranked[5].ranking_resolution == RankingResolution.TIEBREAK_GAME_REQUIRED


def test_three_team_tie_uses_head_to_head_then_previous_season_rank():
    service = RegularSeasonRankingService()

    ranked = service.rank_records(
        records=[
            TeamRegularSeasonRecord("NC", 6, 9, 0, 15, 129, 0),
            TeamRegularSeasonRecord("KT", 6, 9, 0, 15, 129, 0),
            TeamRegularSeasonRecord("LOTTE", 6, 9, 0, 15, 129, 0),
        ],
        games=[
            {
                "home_team_id": "NC",
                "away_team_id": "KT",
                "status": "finished",
                "season_classification": "regular_season",
                "home_score": 5,
                "away_score": 3,
            },
            {
                "home_team_id": "LOTTE",
                "away_team_id": "NC",
                "status": "finished",
                "season_classification": "regular_season",
                "home_score": 3,
                "away_score": 1,
            },
            {
                "home_team_id": "KT",
                "away_team_id": "LOTTE",
                "status": "finished",
                "season_classification": "regular_season",
                "home_score": 2,
                "away_score": 1,
            },
        ],
        previous_regular_season_rank_by_team_id={
            "NC": 5,
            "KT": 6,
            "LOTTE": 7,
        },
    )

    assert [record.team_id for record in ranked] == ["NC", "KT", "LOTTE"]
    assert all(record.ranking_resolution == RankingResolution.RESOLVED for record in ranked)
