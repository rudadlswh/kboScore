from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session


class WeatherRepository:
    def get_latest_weather_for_stadium(self, db: Session, stadium_id: str | None) -> dict | None:
        if not stadium_id:
            return None

        # The current collector schema stores stadium_code and current_icon_name.
        # They are exposed here as the MVP read-side contract fields stadiumId/condition.
        result = db.execute(
            text(
                """
                SELECT
                    ws.stadium_code AS stadium_id,
                    ws.observed_at,
                    ws.current_temp_c AS temperature_c,
                    -- Public weather.condition currently maps to current_icon_name.
                    ws.current_icon_name AS condition,
                    ws.current_rain_mm AS precipitation_mm
                FROM weather_snapshots ws
                WHERE ws.stadium_code = :stadium_id
                ORDER BY ws.observed_at DESC
                LIMIT 1
                """
            ),
            {"stadium_id": stadium_id},
        )
        return result.mappings().first()
