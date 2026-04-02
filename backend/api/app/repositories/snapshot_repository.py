from __future__ import annotations

from collections.abc import Sequence

from sqlalchemy import text
from sqlalchemy.orm import Session


class SnapshotRepository:
    def list_game_snapshots(self, db: Session, game_id: str, *, limit: int) -> Sequence[dict]:
        result = db.execute(
            text(
                """
                SELECT
                    gs.snapshot_at,
                    gs.status,
                    gs.home_score,
                    gs.away_score,
                    gs.inning_state
                FROM game_snapshots gs
                WHERE gs.game_id::text = :game_id
                ORDER BY gs.snapshot_at DESC
                LIMIT :limit
                """
            ),
            {"game_id": game_id, "limit": limit},
        )
        return result.mappings().all()
