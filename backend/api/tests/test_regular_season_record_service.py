from __future__ import annotations

from app.services.regular_season_record_service import RegularSeasonRecordService


def test_regular_season_record_service_filters_to_regular_season_only():
    service = RegularSeasonRecordService()

    summary = service.build_records(
        team_ids=["LG", "DOO", "SSG"],
        games=[
            {
                "home_team_id": "LG",
                "away_team_id": "DOO",
                "status": "finished",
                "season_classification": "regular_season",
                "home_score": 5,
                "away_score": 2,
            },
            {
                "home_team_id": "SSG",
                "away_team_id": "LG",
                "status": "finished",
                "season_classification": "exhibition_preseason",
                "home_score": 1,
                "away_score": 9,
            },
            {
                "home_team_id": "DOO",
                "away_team_id": "SSG",
                "status": "finished",
                "season_classification": "postseason",
                "home_score": 3,
                "away_score": 2,
            },
        ],
    )

    records = {record.team_id: record for record in summary.records}
    assert records["LG"].wins == 1
    assert records["LG"].games_played == 1
    assert records["DOO"].losses == 1
    assert records["SSG"].games_played == 0
    assert records["LG"].remaining_regular_season_games == 143


def test_regular_season_record_service_surfaces_unknown_classification_coverage():
    service = RegularSeasonRecordService()

    summary = service.build_records(
        team_ids=["LG", "DOO"],
        games=[
            {
                "home_team_id": "LG",
                "away_team_id": "DOO",
                "status": "finished",
                "season_classification": "unknown",
                "home_score": 4,
                "away_score": 4,
            }
        ],
    )

    records = {record.team_id: record for record in summary.records}
    assert summary.has_unknown_classification_games is True
    assert records["LG"].unknown_classification_games == 1
    assert records["DOO"].unknown_classification_games == 1
    assert records["LG"].games_played == 0
    assert records["LG"].remaining_regular_season_games == 144
