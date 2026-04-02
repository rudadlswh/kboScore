from __future__ import annotations

import os
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Callable

import psycopg

from collector.db import connect
from collector.utils.hash import stable_json_dumps
from collector.utils.time import now_kst, to_kst


@dataclass(frozen=True, slots=True)
class ManualNotificationSeedResult:
    device_registration_id: str
    notification_event_id: str
    game_id: str


def seed_manual_notification_smoke_target(
    *,
    database_url: str,
    device_token: str,
    favorite_team_code: str = "LG",
    now_at: datetime | None = None,
    db_connection_factory: Callable[[], psycopg.Connection] | None = None,
) -> ManualNotificationSeedResult:
    token = device_token.strip()
    if not token:
        raise ValueError("device_token must not be blank")

    observed_at = to_kst(now_at or now_kst())
    provider_game_id = f"manual-smoke-{observed_at.strftime('%Y%m%d')}"
    home_team_code = "LG"
    away_team_code = "KT"
    event_type = "postponed_confirmed"

    with (db_connection_factory or (lambda: connect(database_url)))() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO teams (code, name_ko, short_name, sort_order)
                VALUES
                    ('LG', 'LG 트윈스', 'LG', 1),
                    ('KT', 'KT 위즈', 'KT', 2)
                ON CONFLICT (code) DO UPDATE
                SET name_ko = EXCLUDED.name_ko,
                    short_name = EXCLUDED.short_name,
                    sort_order = EXCLUDED.sort_order
                """
            )
            cur.execute("SELECT id::text AS id, code FROM teams WHERE code IN ('LG', 'KT')")
            team_rows = list(cur.fetchall())
            team_ids = {row["code"]: row["id"] for row in team_rows}
            favorite_team_id = team_ids.get(favorite_team_code)
            if favorite_team_id is None:
                raise ValueError(f"Unsupported favorite_team_code for manual smoke seed: {favorite_team_code}")

            cur.execute(
                """
                INSERT INTO games (
                    provider,
                    provider_game_id,
                    game_date,
                    scheduled_at,
                    stadium,
                    stadium_code,
                    home_team_id,
                    away_team_id,
                    status,
                    official_provider_game_id,
                    provider_game_id_kind
                ) VALUES (
                    'kbo',
                    %(provider_game_id)s,
                    %(game_date)s,
                    %(scheduled_at)s,
                    '잠실',
                    'JS',
                    %(home_team_id)s::uuid,
                    %(away_team_id)s::uuid,
                    'scheduled',
                    %(provider_game_id)s,
                    'official'
                )
                ON CONFLICT (provider, provider_game_id) DO UPDATE
                SET
                    game_date = EXCLUDED.game_date,
                    scheduled_at = EXCLUDED.scheduled_at,
                    stadium = EXCLUDED.stadium,
                    stadium_code = EXCLUDED.stadium_code,
                    home_team_id = EXCLUDED.home_team_id,
                    away_team_id = EXCLUDED.away_team_id,
                    status = EXCLUDED.status,
                    official_provider_game_id = EXCLUDED.official_provider_game_id,
                    provider_game_id_kind = EXCLUDED.provider_game_id_kind
                RETURNING id::text AS id
                """,
                {
                    "provider_game_id": provider_game_id,
                    "game_date": observed_at.date(),
                    "scheduled_at": observed_at.replace(hour=18, minute=30, second=0, microsecond=0),
                    "home_team_id": team_ids[home_team_code],
                    "away_team_id": team_ids[away_team_code],
                },
            )
            game_id = str(cur.fetchone()["id"])

            cur.execute(
                """
                INSERT INTO device_registrations (
                    device_token,
                    platform,
                    app_version,
                    favorite_team_id,
                    notifications_enabled
                ) VALUES (
                    %(device_token)s,
                    'ios',
                    'manual-smoke',
                    %(favorite_team_id)s::uuid,
                    TRUE
                )
                ON CONFLICT (device_token) DO UPDATE
                SET
                    app_version = EXCLUDED.app_version,
                    favorite_team_id = EXCLUDED.favorite_team_id,
                    notifications_enabled = TRUE
                RETURNING id::text AS id
                """,
                {
                    "device_token": token,
                    "favorite_team_id": favorite_team_id,
                },
            )
            device_registration_id = str(cur.fetchone()["id"])

            event_key = f"manual-smoke:{game_id}:{event_type}:v1"
            payload_json = stable_json_dumps(
                {
                    "manual_smoke": True,
                    "notification_type": event_type,
                    "game_id": game_id,
                }
            )
            notification_event_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{event_key}:{device_registration_id}"))

            cur.execute(
                """
                INSERT INTO notification_events (
                    id,
                    device_registration_id,
                    game_id,
                    event_type,
                    event_key,
                    title,
                    body,
                    payload_json,
                    delivery_status,
                    attempt_count,
                    attempted_at,
                    sent_at,
                    failed_at,
                    failure_reason,
                    next_attempt_at
                ) VALUES (
                    %(notification_event_id)s::uuid,
                    %(device_registration_id)s::uuid,
                    %(game_id)s::uuid,
                    %(event_type)s,
                    %(event_key)s,
                    '경기 우천 취소',
                    '수동 sandbox smoke test 알림입니다.',
                    %(payload_json)s::jsonb,
                    'queued',
                    0,
                    NULL,
                    NULL,
                    NULL,
                    NULL,
                    NULL
                )
                ON CONFLICT (event_key, device_registration_id) DO UPDATE
                SET
                    title = EXCLUDED.title,
                    body = EXCLUDED.body,
                    payload_json = EXCLUDED.payload_json,
                    delivery_status = 'queued',
                    attempt_count = 0,
                    attempted_at = NULL,
                    sent_at = NULL,
                    failed_at = NULL,
                    failure_reason = NULL,
                    next_attempt_at = NULL
                RETURNING id::text AS id
                """,
                {
                    "notification_event_id": notification_event_id,
                    "device_registration_id": device_registration_id,
                    "game_id": game_id,
                    "event_type": event_type,
                    "event_key": event_key,
                    "payload_json": payload_json,
                },
            )
            notification_event_id = str(cur.fetchone()["id"])
        conn.commit()

    return ManualNotificationSeedResult(
        device_registration_id=device_registration_id,
        notification_event_id=notification_event_id,
        game_id=game_id,
    )


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else os.sys.argv[1:])
    if len(args) != 1:
        print("Usage: python seed_notification_smoke.py <sandbox-device-token>")
        return 2

    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        print("Missing required env var: DATABASE_URL")
        return 1

    result = seed_manual_notification_smoke_target(database_url=database_url, device_token=args[0])
    print(f"device_registration_id={result.device_registration_id}")
    print(f"notification_event_id={result.notification_event_id}")
    print(f"game_id={result.game_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
