from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

import psycopg

from collector.utils.hash import sha256_hexdigest, stable_json_dumps


GameScheduleEventType = Literal[
    "postponed_candidate",
    "postponed_confirmed",
    "doubleheader_announced",
    "makeup_scheduled",
    "venue_changed",
    "time_changed",
    "status_corrected",
]


SUPPORTED_GAME_SCHEDULE_EVENT_TYPES: tuple[GameScheduleEventType, ...] = (
    "postponed_candidate",
    "postponed_confirmed",
    "doubleheader_announced",
    "makeup_scheduled",
    "venue_changed",
    "time_changed",
    "status_corrected",
)


@dataclass(frozen=True, slots=True)
class GameEventInsertResult:
    inserted: bool
    event_id: str | None


@dataclass(slots=True)
class GameEventService:
    conn: psycopg.Connection

    def record_event(
        self,
        *,
        game_id: str,
        event_type: GameScheduleEventType,
        confirmed: bool,
        reason: str | None,
        source: str,
        recorded_at: datetime,
        payload_json: dict | None = None,
    ) -> GameEventInsertResult:
        if event_type not in SUPPORTED_GAME_SCHEDULE_EVENT_TYPES:
            raise ValueError(f"Unsupported game schedule event type: {event_type}")

        payload_json = payload_json or {}
        event_key = self._build_event_key(
            game_id=game_id,
            event_type=event_type,
            confirmed=confirmed,
            reason=reason,
            source=source,
            payload_json=payload_json,
        )

        with self.conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO game_schedule_events (
                    game_id,
                    event_type,
                    confirmed,
                    reason,
                    source,
                    recorded_at,
                    payload_json,
                    event_key
                ) VALUES (
                    %(game_id)s::uuid,
                    %(event_type)s,
                    %(confirmed)s,
                    %(reason)s,
                    %(source)s,
                    %(recorded_at)s,
                    %(payload_json)s::jsonb,
                    %(event_key)s
                )
                ON CONFLICT (event_key) DO NOTHING
                RETURNING id::text AS id
                """,
                {
                    "game_id": game_id,
                    "event_type": event_type,
                    "confirmed": confirmed,
                    "reason": reason,
                    "source": source,
                    "recorded_at": recorded_at,
                    "payload_json": stable_json_dumps(payload_json),
                    "event_key": event_key,
                },
            )
            row = cur.fetchone()

        return GameEventInsertResult(inserted=row is not None, event_id=str(row["id"]) if row else None)

    @staticmethod
    def _build_event_key(
        *,
        game_id: str,
        event_type: str,
        confirmed: bool,
        reason: str | None,
        source: str,
        payload_json: dict,
    ) -> str:
        return sha256_hexdigest(
            stable_json_dumps(
                {
                    "game_id": game_id,
                    "event_type": event_type,
                    "confirmed": confirmed,
                    "reason": reason,
                    "source": source,
                    "payload": payload_json,
                }
            )
        )
