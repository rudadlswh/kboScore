import os
from datetime import date

import psycopg
from fastapi import FastAPI, Query
from psycopg.rows import dict_row

app = FastAPI()

DATABASE_URL = os.getenv("DATABASE_URL")


def get_connection():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


@app.get("/health")
def health():
    db_ok = False
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        db_ok = True
    except Exception:
        db_ok = False

    return {
        "status": "ok",
        "db": "connected" if db_ok else "disconnected",
    }


@app.get("/teams")
def get_teams():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id::text AS id,
                    code,
                    name_ko,
                    name_en,
                    short_name,
                    theme_color,
                    logo_asset_name,
                    sort_order,
                    is_active
                FROM teams
                WHERE is_active = TRUE
                ORDER BY sort_order ASC, code ASC
                """
            )
            rows = cur.fetchall()

    return [
        {
            "id": row["id"],
            "code": row["code"],
            "nameKo": row["name_ko"],
            "nameEn": row["name_en"],
            "shortName": row["short_name"],
            "themeColor": row["theme_color"],
            "logoAssetName": row["logo_asset_name"],
            "sortOrder": row["sort_order"],
            "isActive": row["is_active"],
        }
        for row in rows
    ]


@app.get("/schedule/month")
def get_schedule_month(
    year: int = Query(...),
    month: int = Query(..., ge=1, le=12),
    teamCode: str | None = Query(default=None),
):
    month_start = date(year, month, 1)
    if month == 12:
        next_month_start = date(year + 1, 1, 1)
    else:
        next_month_start = date(year, month + 1, 1)

    normalized_team_code = teamCode.strip().upper() if teamCode and teamCode.strip() else None

    query = """
        SELECT
            g.id::text AS id,
            g.game_date,
            CASE
                WHEN g.scheduled_at IS NULL THEN NULL
                ELSE to_char(g.scheduled_at AT TIME ZONE 'Asia/Seoul', 'HH24:MI')
            END AS game_time,
            g.status,
            g.stadium,
            g.home_score,
            g.away_score,
            g.inning_state,
            home.code AS home_code,
            home.name_ko AS home_name_ko,
            home.short_name AS home_short_name,
            home.theme_color AS home_theme_color,
            home.logo_asset_name AS home_logo_asset_name,
            away.code AS away_code,
            away.name_ko AS away_name_ko,
            away.short_name AS away_short_name,
            away.theme_color AS away_theme_color,
            away.logo_asset_name AS away_logo_asset_name
        FROM games g
        JOIN teams home ON home.id = g.home_team_id
        JOIN teams away ON away.id = g.away_team_id
        WHERE g.game_date >= %s
          AND g.game_date < %s
    """
    params = [month_start, next_month_start]

    if normalized_team_code:
        query += """
          AND (home.code = %s OR away.code = %s)
        """
        params.extend([normalized_team_code, normalized_team_code])

    query += """
        ORDER BY
            g.game_date ASC,
            g.scheduled_at ASC,
            away.sort_order ASC,
            home.sort_order ASC
    """

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            rows = cur.fetchall()

    games = [
        {
            "id": row["id"],
            "gameDate": row["game_date"].isoformat(),
            "gameTime": row["game_time"],
            "status": row["status"],
            "stadium": row["stadium"],
            "homeScore": row["home_score"],
            "awayScore": row["away_score"],
            "inningState": row["inning_state"],
            "homeTeam": {
                "code": row["home_code"],
                "nameKo": row["home_name_ko"],
                "shortName": row["home_short_name"],
                "themeColor": row["home_theme_color"],
                "logoAssetName": row["home_logo_asset_name"],
            },
            "awayTeam": {
                "code": row["away_code"],
                "nameKo": row["away_name_ko"],
                "shortName": row["away_short_name"],
                "themeColor": row["away_theme_color"],
                "logoAssetName": row["away_logo_asset_name"],
            },
        }
        for row in rows
    ]

    return {
        "year": year,
        "month": month,
        "totalCount": len(games),
        "games": games,
    }
