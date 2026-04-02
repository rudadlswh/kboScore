from __future__ import annotations

from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

from app.repositories.game_repository import GameRepository
from app.repositories.team_repository import TeamRepository
from app.schemas.standings import (
    PostseasonProbabilityUnavailableReason,
    StandingsItem,
    StandingsRankingResolution,
    StandingsRecentResult,
    StandingsResponse,
)
from app.schemas.team import TeamSummary
from app.services.postseason_qualification_probability_service import (
    PostseasonQualificationProbabilityService,
)
from app.services.regular_season_ranking_service import RankingResolution, RegularSeasonRankingService
from app.services.regular_season_record_service import RegularSeasonRecordService

class StandingsQueryService:
    def __init__(
        self,
        *,
        team_repository: TeamRepository,
        game_repository: GameRepository,
        record_service: RegularSeasonRecordService,
        ranking_service: RegularSeasonRankingService,
        probability_service: PostseasonQualificationProbabilityService,
    ) -> None:
        self.team_repository = team_repository
        self.game_repository = game_repository
        self.record_service = record_service
        self.ranking_service = ranking_service
        self.probability_service = probability_service

    def get_regular_season_standings(self, db: Session, *, season_id: int) -> StandingsResponse:
        team_rows = list(self.team_repository.list_teams_with_ranking_metadata(db))
        season_games = list(
            self.game_repository.list_games_in_range(
                db,
                date_from=date(season_id, 1, 1),
                date_to=date(season_id, 12, 31),
            )
        )
        team_ids = [row["team_id"] for row in team_rows]
        record_summary = self.record_service.build_records(team_ids=team_ids, games=season_games)
        previous_regular_season_rank_by_team_id = {
            row["team_id"]: row.get("previous_regular_season_rank")
            for row in team_rows
        }
        team_name_by_id = {row["team_id"]: row["name_ko"] for row in team_rows}

        ranked_records = self.ranking_service.rank_records(
            records=record_summary.records,
            games=season_games,
            previous_regular_season_rank_by_team_id=previous_regular_season_rank_by_team_id,
        )
        probability_summary = self.probability_service.calculate_probabilities(
            team_ids=team_ids,
            games=season_games,
            previous_regular_season_rank_by_team_id=previous_regular_season_rank_by_team_id,
        )
        recent_results_by_team_id = self._build_recent_results(season_games)

        return StandingsResponse(
            season_id=season_id,
            generated_at=datetime.now(tz=timezone.utc),
            has_unknown_classification_games=record_summary.has_unknown_classification_games,
            standings=[
                StandingsItem(
                    team=TeamSummary(team_id=record.team_id, name_ko=team_name_by_id[record.team_id]),
                    rank=record.rank,
                    wins=record.wins,
                    losses=record.losses,
                    ties=record.ties,
                    games_played=record.games_played,
                    remaining_regular_season_games=record.remaining_regular_season_games,
                    win_percentage=record.win_percentage,
                    recent_results=recent_results_by_team_id.get(record.team_id, []),
                    unknown_classification_games=record.unknown_classification_games,
                    ranking_resolution=self._map_ranking_resolution(record.ranking_resolution),
                    ranking_resolution_position=record.ranking_resolution_position,
                    postseason_qualification_probability=probability_summary.probabilities_by_team_id[record.team_id].probability,
                    postseason_probability_unavailable_reason=self._map_probability_unavailable_reason(
                        probability_summary.probabilities_by_team_id[record.team_id].unavailable_reason
                    ),
                )
                for record in ranked_records
            ],
        )

    @staticmethod
    def _map_ranking_resolution(value: RankingResolution) -> StandingsRankingResolution:
        if value == RankingResolution.TIEBREAK_GAME_REQUIRED:
            return StandingsRankingResolution.TIEBREAK_GAME_REQUIRED
        return StandingsRankingResolution.RESOLVED

    @staticmethod
    def _map_probability_unavailable_reason(
        value,
    ) -> PostseasonProbabilityUnavailableReason | None:
        if value is None:
            return None
        return PostseasonProbabilityUnavailableReason(value)

    @staticmethod
    def _build_recent_results(games: list[dict]) -> dict[str, list[StandingsRecentResult]]:
        completed_regular_season_games = [
            game
            for game in games
            if game.get("season_classification") == "regular_season"
            and game.get("status") == "finished"
            and game.get("home_score") is not None
            and game.get("away_score") is not None
        ]
        completed_regular_season_games.sort(
            key=lambda game: (
                game.get("scheduled_at") or datetime.min.replace(tzinfo=timezone.utc),
                game.get("game_id"),
            ),
            reverse=True,
        )

        recent_results_by_team_id: dict[str, list[StandingsRecentResult]] = {}
        for game in completed_regular_season_games:
            home_team_id = game["home_team_id"]
            away_team_id = game["away_team_id"]
            home_score = game["home_score"]
            away_score = game["away_score"]

            if home_score == away_score:
                home_result = StandingsRecentResult.TIE
                away_result = StandingsRecentResult.TIE
            elif home_score > away_score:
                home_result = StandingsRecentResult.WIN
                away_result = StandingsRecentResult.LOSS
            else:
                home_result = StandingsRecentResult.LOSS
                away_result = StandingsRecentResult.WIN

            recent_results_by_team_id.setdefault(home_team_id, [])
            if len(recent_results_by_team_id[home_team_id]) < 5:
                recent_results_by_team_id[home_team_id].append(home_result)

            recent_results_by_team_id.setdefault(away_team_id, [])
            if len(recent_results_by_team_id[away_team_id]) < 5:
                recent_results_by_team_id[away_team_id].append(away_result)

        return recent_results_by_team_id
