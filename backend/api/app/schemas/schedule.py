from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel
from app.schemas.game import GameSeasonClassification, GameStatus


class ScheduleMonthTeam(ApiModel):
    team_id: str
    name_ko: str
    short_name: str


class ScheduleMonthGameItem(ApiModel):
    game_id: str
    scheduled_at: datetime | None = None
    status: GameStatus
    season_classification: GameSeasonClassification = GameSeasonClassification.UNKNOWN
    stadium: str | None = None
    home_team: ScheduleMonthTeam
    away_team: ScheduleMonthTeam
    home_score: int | None = None
    away_score: int | None = None
    inning_state: str | None = None


class ScheduleMonthResponse(ApiModel):
    year: int
    month: int
    total_count: int
    games: list[ScheduleMonthGameItem]
