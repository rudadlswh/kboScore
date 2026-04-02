from __future__ import annotations

from datetime import date, datetime
from enum import StrEnum

from app.schemas.common import ApiModel
from app.schemas.team import TeamSummary
from app.schemas.weather import WeatherCurrent


class GameStatus(StrEnum):
    SCHEDULED = "scheduled"
    LIVE = "live"
    FINISHED = "finished"
    POSTPONED = "postponed"
    CANCELLED = "cancelled"
    SUSPENDED = "suspended"
    UNKNOWN = "unknown"


class GameSeasonClassification(StrEnum):
    UNKNOWN = "unknown"
    REGULAR_SEASON = "regular_season"
    EXHIBITION_PRESEASON = "exhibition_preseason"
    POSTSEASON = "postseason"


class StadiumSummary(ApiModel):
    stadium_id: str | None = None
    name_ko: str | None = None


class ScoreSummary(ApiModel):
    home: int | None = None
    away: int | None = None


class GameListItem(ApiModel):
    game_id: str
    scheduled_at: datetime | None = None
    home_team: TeamSummary
    away_team: TeamSummary
    stadium: StadiumSummary
    status: GameStatus
    season_classification: GameSeasonClassification = GameSeasonClassification.UNKNOWN
    score: ScoreSummary
    inning_state: str | None = None
    is_double_header: bool = False
    is_postponed: bool = False


class GamesResponse(ApiModel):
    date: date
    games: list[GameListItem]


class GameDetailResponse(ApiModel):
    game_id: str
    provider_game_id: str
    official_provider_game_id: str | None = None
    scheduled_at: datetime | None = None
    home_team: TeamSummary
    away_team: TeamSummary
    stadium: StadiumSummary
    status: GameStatus
    season_classification: GameSeasonClassification = GameSeasonClassification.UNKNOWN
    score: ScoreSummary
    inning_state: str | None = None
    latest_snapshot_at: datetime | None = None
    weather: WeatherCurrent | None = None


class SnapshotResponse(ApiModel):
    snapshot_at: datetime
    status: GameStatus
    score: ScoreSummary
    inning_state: str | None = None


class GameSnapshotsResponse(ApiModel):
    game_id: str
    snapshots: list[SnapshotResponse]


class TeamGameScore(ApiModel):
    my_team: int | None = None
    opponent: int | None = None


class TeamGameItem(ApiModel):
    game_id: str
    scheduled_at: datetime | None = None
    opponent_team: TeamSummary
    is_home: bool
    status: GameStatus
    season_classification: GameSeasonClassification = GameSeasonClassification.UNKNOWN
    score: TeamGameScore
    inning_state: str | None = None
    stadium: StadiumSummary


class TeamGamesResponse(ApiModel):
    team_id: str
    date_from: date
    date_to: date
    games: list[TeamGameItem]
