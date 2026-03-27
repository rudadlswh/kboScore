from __future__ import annotations

from datetime import date, datetime
from typing import Any

import psycopg


def seed_default_teams(conn: psycopg.Connection) -> dict[str, str]:
    teams = [
        ("LG", "LG 트윈스", "LG"),
        ("KT", "KT 위즈", "KT"),
        ("DOOSAN", "두산 베어스", "두산"),
        ("KIA", "KIA 타이거즈", "KIA"),
        ("LOTTE", "롯데 자이언츠", "롯데"),
        ("SAMSUNG", "삼성 라이온즈", "삼성"),
        ("HANWHA", "한화 이글스", "한화"),
        ("KIWOOM", "키움 히어로즈", "키움"),
        ("NC", "NC 다이노스", "NC"),
        ("SSG", "SSG 랜더스", "SSG"),
    ]

    code_to_id: dict[str, str] = {}
    with conn.cursor() as cur:
        for sort_order, (code, name_ko, short_name) in enumerate(teams, start=1):
            cur.execute(
                """
                INSERT INTO teams (code, name_ko, short_name, sort_order)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (code) DO UPDATE
                SET name_ko = EXCLUDED.name_ko,
                    short_name = EXCLUDED.short_name,
                    sort_order = EXCLUDED.sort_order
                RETURNING id::text AS id
                """,
                (code, name_ko, short_name, sort_order),
            )
            row = cur.fetchone()
            code_to_id[code] = str(row["id"])
    conn.commit()
    return code_to_id


def insert_game(
    conn: psycopg.Connection,
    *,
    provider: str = "kbo",
    provider_game_id: str,
    game_date: date,
    scheduled_at: datetime | None,
    stadium: str,
    stadium_code: str | None,
    home_team_id: str,
    away_team_id: str,
    status: str = "scheduled",
    home_score: int = 0,
    away_score: int = 0,
    inning_state: str | None = None,
    is_cancelled: bool = False,
    is_postponed: bool = False,
    source_updated_at: datetime | None = None,
    official_provider_game_id: str | None = None,
    provider_game_id_kind: str = "official",
) -> str:
    with conn.cursor() as cur:
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
                home_score,
                away_score,
                inning_state,
                is_cancelled,
                is_postponed,
                source_updated_at,
                official_provider_game_id,
                provider_game_id_kind
            ) VALUES (
                %(provider)s,
                %(provider_game_id)s,
                %(game_date)s,
                %(scheduled_at)s,
                %(stadium)s,
                %(stadium_code)s,
                %(home_team_id)s::uuid,
                %(away_team_id)s::uuid,
                %(status)s,
                %(home_score)s,
                %(away_score)s,
                %(inning_state)s,
                %(is_cancelled)s,
                %(is_postponed)s,
                %(source_updated_at)s,
                %(official_provider_game_id)s,
                %(provider_game_id_kind)s
            )
            RETURNING id::text AS id
            """,
            {
                "provider": provider,
                "provider_game_id": provider_game_id,
                "game_date": game_date,
                "scheduled_at": scheduled_at,
                "stadium": stadium,
                "stadium_code": stadium_code,
                "home_team_id": home_team_id,
                "away_team_id": away_team_id,
                "status": status,
                "home_score": home_score,
                "away_score": away_score,
                "inning_state": inning_state,
                "is_cancelled": is_cancelled,
                "is_postponed": is_postponed,
                "source_updated_at": source_updated_at,
                "official_provider_game_id": official_provider_game_id,
                "provider_game_id_kind": provider_game_id_kind,
            },
        )
        row = cur.fetchone()
    conn.commit()
    return str(row["id"])


def insert_device_registration(
    conn: psycopg.Connection,
    *,
    device_token: str,
    favorite_team_id: str | None,
    notifications_enabled: bool = True,
    platform: str = "ios",
    app_version: str = "1.0.0",
) -> str:
    with conn.cursor() as cur:
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
                %(platform)s,
                %(app_version)s,
                %(favorite_team_id)s::uuid,
                %(notifications_enabled)s
            )
            RETURNING id::text AS id
            """,
            {
                "device_token": device_token,
                "platform": platform,
                "app_version": app_version,
                "favorite_team_id": favorite_team_id,
                "notifications_enabled": notifications_enabled,
            },
        )
        row = cur.fetchone()
    conn.commit()
    return str(row["id"])


def execute_sql(conn: psycopg.Connection, sql_text: str) -> None:
    with conn.cursor() as cur:
        cur.execute(sql_text)
    conn.commit()


def fetch_game_by_provider_game_id(conn: psycopg.Connection, provider_game_id: str) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM games WHERE provider_game_id = %s", (provider_game_id,))
        return cur.fetchone()


def fetch_game_by_id(conn: psycopg.Connection, game_id: str) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM games WHERE id = %s::uuid", (game_id,))
        return cur.fetchone()


def fetch_weather_snapshots_for_game(conn: psycopg.Connection, game_id: str) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM weather_snapshots WHERE game_id = %s::uuid ORDER BY observed_at ASC",
            (game_id,),
        )
        return list(cur.fetchall())


def fetch_game_snapshots_for_game(conn: psycopg.Connection, game_id: str) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM game_snapshots WHERE game_id = %s::uuid ORDER BY snapshot_at ASC",
            (game_id,),
        )
        return list(cur.fetchall())


def fetch_notification_events_for_game(conn: psycopg.Connection, game_id: str) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM notification_events WHERE game_id = %s::uuid ORDER BY created_at ASC",
            (game_id,),
        )
        return list(cur.fetchall())


def count_rows(conn: psycopg.Connection, table_name: str) -> int:
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS count FROM {table_name}")
        row = cur.fetchone()
    return int(row["count"])
