from __future__ import annotations

from dataclasses import dataclass

import psycopg

from collector.models.weather_models import NormalizedWeatherSnapshot
from collector.utils.hash import build_weather_content_hash, stable_json_dumps


@dataclass(slots=True)
class WeatherSnapshotService:
    conn: psycopg.Connection

    def build_content_hash(self, snapshot: NormalizedWeatherSnapshot) -> str:
        return build_weather_content_hash(snapshot)

    def insert_if_changed(self, game_id: str, snapshot: NormalizedWeatherSnapshot) -> bool:
        """
        Insert a weather snapshot only when its content hash differs from the latest stored snapshot.
        Returns True when inserted.
        """
        content_hash = self.build_content_hash(snapshot)
        payload_json = stable_json_dumps(snapshot.to_payload_json())

        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT content_hash
                FROM weather_snapshots
                WHERE game_id = %s::uuid
                ORDER BY observed_at DESC
                LIMIT 1
                """,
                (game_id,),
            )
            row = cur.fetchone()
            if row is not None and row["content_hash"] == content_hash:
                return False

            cur.execute(
                """
                INSERT INTO weather_snapshots (
                    game_id,
                    observed_at,
                    source_name,
                    stadium_code,
                    current_icon_code,
                    current_icon_name,
                    current_temp_c,
                    current_rain_mm,
                    current_rain_raw,
                    current_humidity_pct,
                    current_wind_speed_ms,
                    forecast_issued_at,
                    content_hash,
                    payload_json
                ) VALUES (
                    %(game_id)s::uuid,
                    %(observed_at)s,
                    %(source_name)s,
                    %(stadium_code)s,
                    %(current_icon_code)s,
                    %(current_icon_name)s,
                    %(current_temp_c)s,
                    %(current_rain_mm)s,
                    %(current_rain_raw)s,
                    %(current_humidity_pct)s,
                    %(current_wind_speed_ms)s,
                    %(forecast_issued_at)s,
                    %(content_hash)s,
                    %(payload_json)s::jsonb
                )
                """,
                {
                    "game_id": game_id,
                    "observed_at": snapshot.source_observed_at,
                    "source_name": snapshot.source_name,
                    "stadium_code": snapshot.stadium_code,
                    "current_icon_code": snapshot.current_icon_code,
                    "current_icon_name": snapshot.current_icon_name,
                    "current_temp_c": snapshot.current_temp_c,
                    "current_rain_mm": snapshot.current_rain_mm,
                    "current_rain_raw": snapshot.current_rain_raw,
                    "current_humidity_pct": snapshot.current_humidity_pct,
                    "current_wind_speed_ms": snapshot.current_wind_speed_ms,
                    "forecast_issued_at": snapshot.forecast_issued_at,
                    "content_hash": content_hash,
                    "payload_json": payload_json,
                },
            )
        return True
