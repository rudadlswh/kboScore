from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class WeatherCurrent(ApiModel):
    temperature_c: float | None = None
    condition: str | None = None
    precipitation_mm: float | None = None
    observed_at: datetime | None = None


class GameWeatherResponse(ApiModel):
    game_id: str
    stadium_id: str | None = None
    current: WeatherCurrent | None = None
