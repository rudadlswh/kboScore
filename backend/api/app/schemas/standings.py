from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from app.schemas.common import ApiModel
from app.schemas.team import TeamSummary


class StandingsRecentResult(StrEnum):
    WIN = "win"
    LOSS = "loss"
    TIE = "tie"


class StandingsRankingResolution(StrEnum):
    RESOLVED = "resolved"
    TIEBREAK_GAME_REQUIRED = "tiebreak_game_required"


class PostseasonProbabilityUnavailableReason(StrEnum):
    UNKNOWN_CLASSIFICATION_GAMES = "unknown_classification_games"
    INCOMPLETE_REGULAR_SEASON_SCHEDULE = "incomplete_regular_season_schedule"
    INSUFFICIENT_COMPLETED_REGULAR_SEASON_GAMES = "insufficient_completed_regular_season_games"


class StandingsItem(ApiModel):
    team: TeamSummary
    rank: int
    wins: int
    losses: int
    ties: int
    games_played: int
    remaining_regular_season_games: int
    win_percentage: float | None = None
    recent_results: list[StandingsRecentResult]
    unknown_classification_games: int = 0
    ranking_resolution: StandingsRankingResolution = StandingsRankingResolution.RESOLVED
    ranking_resolution_position: int | None = None
    postseason_qualification_probability: float | None = None
    postseason_probability_unavailable_reason: PostseasonProbabilityUnavailableReason | None = None


class StandingsResponse(ApiModel):
    season_id: int
    generated_at: datetime
    has_unknown_classification_games: bool
    standings: list[StandingsItem]
