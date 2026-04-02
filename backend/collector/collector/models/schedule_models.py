from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime

from collector.models.season_classification import GameSeasonClassification


@dataclass(frozen=True, slots=True)
class NormalizedScheduleGame:
    provider: str
    provider_game_id: str
    official_provider_game_id: str | None
    provider_game_id_kind: str
    game_date: date
    scheduled_at: datetime | None
    stadium: str
    stadium_code: str | None
    home_team_code: str
    away_team_code: str
    status: str
    season_classification: GameSeasonClassification
    source_name: str

    def __post_init__(self) -> None:
        if self.provider != "kbo":
            raise ValueError("provider must be 'kbo' for MVP bootstrap")
        if self.provider_game_id_kind not in {"official", "derived"}:
            raise ValueError("provider_game_id_kind must be 'official' or 'derived'")
        if self.status not in {"scheduled", "live", "finished", "postponed", "cancelled"}:
            raise ValueError(f"Unsupported status: {self.status}")
        if self.season_classification not in set(GameSeasonClassification):
            raise ValueError(f"Unsupported season_classification: {self.season_classification}")
        if not self.provider_game_id:
            raise ValueError("provider_game_id must not be blank")
        if not self.home_team_code or not self.away_team_code:
            raise ValueError("home_team_code and away_team_code must not be blank")
