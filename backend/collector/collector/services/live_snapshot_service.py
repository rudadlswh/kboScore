from __future__ import annotations

from dataclasses import dataclass
import logging

import psycopg

from collector.models.live_models import NormalizedLiveGameState
from collector.utils.hash import (
    build_live_change_detection_hash,
    sha256_hexdigest,
    stable_json_dumps,
)

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class LiveSnapshotService:
    conn: psycopg.Connection

    def build_change_hash(self, state: NormalizedLiveGameState) -> str:
        return build_live_change_detection_hash(state)

    def insert_if_changed(self, game_id: str, state: NormalizedLiveGameState) -> bool:
        """
        Insert a live snapshot only when its change-detection hash differs from the latest stored snapshot.
        Returns True when inserted.
        """
        payload_json = state.to_payload_json()
        change_hash = self.build_change_hash(state)

        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT payload_json
                FROM game_snapshots
                WHERE game_id = %s::uuid
                ORDER BY snapshot_at DESC
                LIMIT 1
                """,
                (game_id,),
            )
            row = cur.fetchone()
            if row is not None:
                previous_payload = NormalizedLiveGameState.change_detection_payload_from_payload_json(row["payload_json"])
                previous_hash = sha256_hexdigest(stable_json_dumps(previous_payload))
                if previous_hash == change_hash:
                    logger.info(
                        "live_snapshot_skipped_unchanged",
                        extra={
                            "game_id": game_id,
                            "snapshot_status": state.status,
                            "provider_game_ref": state.provider_game_ref,
                        },
                    )
                    return False

            cur.execute(
                """
                INSERT INTO game_snapshots (
                    game_id,
                    snapshot_at,
                    status,
                    inning_state,
                    home_score,
                    away_score,
                    payload_json
                ) VALUES (
                    %(game_id)s::uuid,
                    %(snapshot_at)s,
                    %(status)s,
                    %(inning_state)s,
                    %(home_score)s,
                    %(away_score)s,
                    %(payload_json)s::jsonb
                )
                """,
                {
                    "game_id": game_id,
                    "snapshot_at": state.source_observed_at,
                    "status": state.status,
                    "inning_state": state.inning_state,
                    "home_score": state.home_score,
                    "away_score": state.away_score,
                    "payload_json": stable_json_dumps(payload_json),
                },
            )
        logger.info(
            "live_snapshot_inserted",
            extra={
                "game_id": game_id,
                "snapshot_status": state.status,
                "provider_game_ref": state.provider_game_ref,
            },
        )
        return True
