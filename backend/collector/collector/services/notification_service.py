from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import psycopg

from collector.utils.hash import stable_json_dumps
from collector.utils.time import recent_kst_window_start, to_kst


NOTIFIABLE_GAME_EVENT_TYPES: tuple[str, ...] = (
    "postponed_confirmed",
    "time_changed",
    "venue_changed",
)


@dataclass(frozen=True, slots=True)
class GameEventNotificationSummary:
    candidate_events: int
    target_devices: int
    inserted_notification_events: int
    skipped_duplicates: int


@dataclass(slots=True)
class NotificationService:
    conn: psycopg.Connection

    def create_game_event_notification_events(
        self,
        observed_at: datetime,
        recent_hours: int = 24,
    ) -> GameEventNotificationSummary:
        """
        Read canonical game_schedule_events and create deduped outbound notification_events.

        Roles are intentionally separate:
        - game_schedule_events: authoritative append-only game history
        - notification_events: per-device outbound ledger only

        The scan is bounded to recent recorded_at values to keep the job operationally cheap.
        Dedupe relies on the canonical event's semantic event_key plus device_registration_id.
        """
        observed_at = to_kst(observed_at)
        recent_window_start = recent_kst_window_start(observed_at, hours=recent_hours)
        summary = GameEventNotificationSummary(
            candidate_events=0,
            target_devices=0,
            inserted_notification_events=0,
            skipped_duplicates=0,
        )

        event_rows = self._load_candidate_events(recent_window_start)
        candidate_events = len(event_rows)
        target_devices = 0
        inserted_notification_events = 0
        skipped_duplicates = 0

        for event_row in event_rows:
            device_ids = self._load_target_device_ids(
                home_team_id=event_row["home_team_id"],
                away_team_id=event_row["away_team_id"],
            )
            if not device_ids:
                continue

            target_devices += len(device_ids)
            title, body, payload_json = self._build_notification_content(event_row)
            notification_event_key = f"kbo:game-event:{event_row['canonical_event_key']}:v1"

            for device_id in device_ids:
                inserted = self._insert_notification_event(
                    device_registration_id=device_id,
                    game_id=event_row["game_id"],
                    event_type=event_row["event_type"],
                    event_key=notification_event_key,
                    title=title,
                    body=body,
                    payload_json=payload_json,
                )
                if inserted:
                    inserted_notification_events += 1
                else:
                    skipped_duplicates += 1

        return GameEventNotificationSummary(
            candidate_events=candidate_events,
            target_devices=target_devices,
            inserted_notification_events=inserted_notification_events,
            skipped_duplicates=skipped_duplicates,
        )

    def _load_candidate_events(self, recent_window_start: datetime) -> list[dict]:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    gse.id::text AS game_schedule_event_id,
                    gse.game_id::text AS game_id,
                    gse.event_type,
                    gse.confirmed,
                    gse.reason,
                    gse.source,
                    gse.recorded_at,
                    gse.payload_json,
                    gse.event_key AS canonical_event_key,
                    g.provider_game_id,
                    g.official_provider_game_id,
                    g.game_date,
                    g.scheduled_at,
                    g.stadium,
                    g.stadium_code,
                    g.home_team_id::text AS home_team_id,
                    g.away_team_id::text AS away_team_id,
                    home.short_name AS home_short_name,
                    away.short_name AS away_short_name
                FROM game_schedule_events gse
                JOIN games g ON g.id = gse.game_id
                JOIN teams home ON home.id = g.home_team_id
                JOIN teams away ON away.id = g.away_team_id
                WHERE gse.recorded_at >= %(recent_window_start)s
                  AND gse.event_type = ANY(%(event_types)s)
                ORDER BY gse.recorded_at DESC, gse.id DESC
                """,
                {
                    "recent_window_start": recent_window_start,
                    "event_types": list(NOTIFIABLE_GAME_EVENT_TYPES),
                },
            )
            return list(cur.fetchall())

    def _load_target_device_ids(self, *, home_team_id: str, away_team_id: str) -> list[str]:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT DISTINCT dr.id::text AS id
                FROM device_registrations dr
                WHERE dr.notifications_enabled = TRUE
                  AND NULLIF(BTRIM(dr.device_token), '') IS NOT NULL
                  AND dr.favorite_team_id IN (%s::uuid, %s::uuid)
                ORDER BY id ASC
                """,
                (home_team_id, away_team_id),
            )
            rows = list(cur.fetchall())
        return [str(row["id"]) for row in rows]

    def _insert_notification_event(
        self,
        *,
        device_registration_id: str,
        game_id: str,
        event_type: str,
        event_key: str,
        title: str,
        body: str,
        payload_json: dict,
    ) -> bool:
        with self.conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO notification_events (
                    device_registration_id,
                    game_id,
                    event_type,
                    event_key,
                    title,
                    body,
                    payload_json,
                    delivery_status
                ) VALUES (
                    %(device_registration_id)s::uuid,
                    %(game_id)s::uuid,
                    %(event_type)s,
                    %(event_key)s,
                    %(title)s,
                    %(body)s,
                    %(payload_json)s::jsonb,
                    'queued'
                )
                ON CONFLICT (event_key, device_registration_id) DO NOTHING
                RETURNING id::text AS id
                """,
                {
                    "device_registration_id": device_registration_id,
                    "game_id": game_id,
                    "event_type": event_type,
                    "event_key": event_key,
                    "title": title,
                    "body": body,
                    "payload_json": stable_json_dumps(payload_json),
                },
            )
            row = cur.fetchone()
        return row is not None

    def _build_notification_content(self, event_row: dict) -> tuple[str, str, dict]:
        event_type = str(event_row["event_type"])
        payload_json = dict(event_row["payload_json"] or {})
        away_short_name = event_row["away_short_name"]
        home_short_name = event_row["home_short_name"]

        if event_type == "postponed_confirmed":
            title = "경기 우천 취소" if event_row["reason"] == "rain" else "경기 연기 확정"
            if event_row["reason"] == "rain":
                body = f"{away_short_name} vs {home_short_name} 경기가 우천으로 취소되었습니다."
            else:
                body = f"{away_short_name} vs {home_short_name} 경기가 연기되었습니다."
        elif event_type == "time_changed":
            old_time = self._format_time_text(payload_json.get("old_scheduled_at"))
            new_time = self._format_time_text(payload_json.get("new_scheduled_at"))
            title = "경기 시간 변경"
            if old_time and new_time:
                body = f"{away_short_name} vs {home_short_name} 경기 시간이 {old_time}에서 {new_time}로 변경되었습니다."
            else:
                body = f"{away_short_name} vs {home_short_name} 경기 시간이 변경되었습니다."
        elif event_type == "venue_changed":
            old_stadium = payload_json.get("old_stadium") or payload_json.get("old_stadium_code") or "기존 구장"
            new_stadium = payload_json.get("new_stadium") or payload_json.get("new_stadium_code") or "변경 구장"
            title = "경기 장소 변경"
            body = f"{away_short_name} vs {home_short_name} 경기 장소가 {old_stadium}에서 {new_stadium}(으)로 변경되었습니다."
        else:  # pragma: no cover - guarded by NOTIFIABLE_GAME_EVENT_TYPES
            raise ValueError(f"Unsupported notifiable event type: {event_type}")

        return (
            title,
            body,
            {
                "game_id": event_row["game_id"],
                "provider_game_id": event_row["provider_game_id"],
                "official_provider_game_id": event_row["official_provider_game_id"],
                "game_date": event_row["game_date"],
                "scheduled_at": event_row["scheduled_at"],
                "stadium": event_row["stadium"],
                "stadium_code": event_row["stadium_code"],
                "game_schedule_event_id": event_row["game_schedule_event_id"],
                "canonical_event_key": event_row["canonical_event_key"],
                "event_type": event_type,
                "confirmed": bool(event_row["confirmed"]),
                "reason": event_row["reason"],
                "source": event_row["source"],
                "recorded_at": event_row["recorded_at"],
                "notification_type": event_type,
                "event_payload": payload_json,
            },
        )

    @staticmethod
    def _format_time_text(value: object) -> str | None:
        if not value:
            return None
        try:
            parsed = to_kst(datetime.fromisoformat(str(value)))
        except ValueError:
            return str(value)
        return parsed.strftime("%m/%d %H:%M")
