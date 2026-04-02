from __future__ import annotations

from collections.abc import Sequence
from datetime import date

from sqlalchemy import text
from sqlalchemy.orm import Session


class EventRepository:
    def list_game_events(self, db: Session, game_id: str) -> Sequence[dict]:
        result = db.execute(
            text(
                """
                SELECT
                    gse.event_type,
                    gse.confirmed,
                    gse.reason,
                    gse.recorded_at
                FROM game_schedule_events gse
                WHERE gse.game_id::text = :game_id
                ORDER BY gse.recorded_at DESC, gse.id DESC
                """
            ),
            {"game_id": game_id},
        )
        return result.mappings().all()

    def list_events(
        self,
        db: Session,
        *,
        event_date: date,
        team_id: str | None = None,
        event_type: str | None = None,
    ) -> Sequence[dict]:
        query = """
            SELECT
                gse.game_id::text AS game_id,
                gse.event_type,
                gse.confirmed,
                gse.reason,
                gse.recorded_at
            FROM game_schedule_events gse
            JOIN games g ON g.id = gse.game_id
            JOIN teams home ON home.id = g.home_team_id
            JOIN teams away ON away.id = g.away_team_id
            WHERE DATE(gse.recorded_at AT TIME ZONE 'Asia/Seoul') = :event_date
        """
        params: dict[str, object] = {"event_date": event_date}

        if team_id:
            query += """
                AND (
                    home.code = :team_id
                    OR away.code = :team_id
                )
            """
            params["team_id"] = team_id

        if event_type:
            query += " AND gse.event_type = :event_type"
            params["event_type"] = event_type

        query += " ORDER BY gse.recorded_at DESC, gse.id DESC"
        result = db.execute(text(query), params)
        return result.mappings().all()
