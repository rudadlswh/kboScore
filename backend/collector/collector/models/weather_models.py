from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True, slots=True)
class NormalizedWeatherSnapshot:
    source_name: str
    source_observed_at: datetime
    stadium_code: str
    stadium_name: str
    forecast_issued_at: datetime | None
    home_team_code: str | None
    away_team_code: str | None
    scheduled_game_time: str | None
    current_icon_code: str | None
    current_icon_name: str | None
    current_temp_c: float | None
    current_rain_mm: float | None
    current_rain_raw: str | None
    current_humidity_pct: int | None
    current_wind_speed_ms: float | None
    status_text: str | None
    raw_payload: dict

    def __post_init__(self) -> None:
        if not self.stadium_code:
            raise ValueError("stadium_code must not be blank")
        if not self.source_name:
            raise ValueError("source_name must not be blank")

    def content_hash_payload(self) -> dict:
        return {
            "stadium_code": self.stadium_code,
            "forecast_issued_at": self.forecast_issued_at.isoformat() if self.forecast_issued_at else None,
            "home_team_code": self.home_team_code,
            "away_team_code": self.away_team_code,
            "current_icon_code": self.current_icon_code,
            "current_icon_name": self.current_icon_name,
            "current_temp_c": self.current_temp_c,
            "current_rain_mm": self.current_rain_mm,
            "current_rain_raw": self.current_rain_raw,
            "current_humidity_pct": self.current_humidity_pct,
            "current_wind_speed_ms": self.current_wind_speed_ms,
            "status_text": self.status_text,
        }

    def to_payload_json(self) -> dict:
        return {
            "source_name": self.source_name,
            "source_observed_at": self.source_observed_at.isoformat(),
            "stadium_code": self.stadium_code,
            "stadium_name": self.stadium_name,
            "forecast_issued_at": self.forecast_issued_at.isoformat() if self.forecast_issued_at else None,
            "game_context": {
                "home_team_code": self.home_team_code,
                "away_team_code": self.away_team_code,
                "scheduled_game_time": self.scheduled_game_time,
            },
            "current": {
                "icon_code": self.current_icon_code,
                "icon_name": self.current_icon_name,
                "temp_c": self.current_temp_c,
                "rain_mm": self.current_rain_mm,
                "rain_raw": self.current_rain_raw,
                "humidity_pct": self.current_humidity_pct,
                "wind_speed_ms": self.current_wind_speed_ms,
            },
            "status_text": self.status_text,
            "raw": self.raw_payload,
        }

    def indicates_cancellation_text(self) -> bool:
        return bool(self.status_text and "취소" in self.status_text)
