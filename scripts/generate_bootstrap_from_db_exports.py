#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import UUID

KST = timezone(timedelta(hours=9))
UTC = timezone.utc

FINISHED_STATUSES = {"finished", "final", "ended", "complete"}
LIVE_STATUSES = {"live", "inprogress", "in_progress", "progress", "playing"}
SCHEDULED_STATUSES = {"scheduled", "pre", "pending", "planned"}


def load_json_list(path: Path, label: str) -> list[dict[str, Any]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError(f"{label} must be a JSON array: {path}")
    if not all(isinstance(item, dict) for item in raw):
        raise ValueError(f"{label} must contain only JSON objects: {path}")
    return raw


def parse_datetime(value: Any, field_name: str) -> datetime:
    if value is None:
        raise ValueError(f"{field_name} is required but missing.")

    text = str(value).strip()
    if not text:
        raise ValueError(f"{field_name} is empty.")

    normalized = text.replace("Z", "+00:00")
    parsed: datetime | None = None

    for parser in (
        lambda s: datetime.fromisoformat(s),
        lambda s: datetime.strptime(s, "%Y-%m-%d %H:%M:%S.%f %z"),
        lambda s: datetime.strptime(s, "%Y-%m-%d %H:%M:%S %z"),
    ):
        try:
            parsed = parser(normalized)
            break
        except ValueError:
            continue

    if parsed is None:
        raise ValueError(f"{field_name} has unsupported datetime format: {text}")

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)

    return parsed.astimezone(KST)


def normalize_team_id(team_row: dict[str, Any]) -> str:
    code = str(team_row.get("code") or "").strip().lower()
    if code:
        return code
    logo = str(team_row.get("logo_asset_name") or "").strip().lower()
    if logo:
        return logo
    raise ValueError(f"Team row is missing both code and logo_asset_name: {team_row}")


def map_status(game_row: dict[str, Any]) -> tuple[str, str]:
    if bool(game_row.get("is_cancelled")):
        return "CANCELLED", "취소"
    if bool(game_row.get("is_postponed")):
        return "DELAY", "연기"

    raw = str(game_row.get("status") or "").strip().lower()
    if raw in FINISHED_STATUSES:
        return "FINAL", "종료"
    if raw in LIVE_STATUSES:
        return "LIVE", "진행중"
    if raw in SCHEDULED_STATUSES:
        return "PRE", "경기 예정"

    raise ValueError(
        f"Unsupported game status '{game_row.get('status')}' for game id={game_row.get('id')}"
    )


def as_int_or_none(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError(f"Boolean score value is invalid: {value}")
    return int(value)


def convert_teams(team_rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, str]]:
    rows = sorted(
        team_rows,
        key=lambda row: (
            int(row.get("sort_order") or 9999),
            str(row.get("code") or ""),
        ),
    )

    teams: list[dict[str, Any]] = []
    db_to_app: dict[str, str] = {}
    seen_app_ids: set[str] = set()

    for row in rows:
        db_id = str(row.get("id") or "").strip()
        if not db_id:
            raise ValueError(f"Team row is missing id: {row}")

        app_id = normalize_team_id(row)
        if app_id in seen_app_ids:
            raise ValueError(f"Duplicate app team id generated: {app_id}")
        seen_app_ids.add(app_id)
        db_to_app[db_id] = app_id

        short_name = str(row.get("short_name") or row.get("code") or app_id.upper()).strip()
        name_ko = str(row.get("name_ko") or short_name).strip()
        name_en = str(row.get("name_en") or name_ko).strip()
        mark_text = short_name

        teams.append(
            {
                "id": app_id,
                "name": name_ko,
                "short_name": short_name,
                "english_name": name_en,
                "mark_text": mark_text,
            }
        )

    return teams, db_to_app


def convert_games(game_rows: list[dict[str, Any]], db_to_app_team_id: dict[str, str]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []

    def game_sort_key(row: dict[str, Any]) -> tuple[datetime, str]:
        return parse_datetime(row.get("scheduled_at"), "scheduled_at"), str(row.get("id") or "")

    for row in sorted(game_rows, key=game_sort_key):
        game_id = str(row.get("id") or "").strip()
        if not game_id:
            raise ValueError(f"Game row missing id: {row}")
        UUID(game_id)

        home_db_id = str(row.get("home_team_id") or "").strip()
        away_db_id = str(row.get("away_team_id") or "").strip()
        if home_db_id not in db_to_app_team_id:
            raise ValueError(f"Unmapped home_team_id: {home_db_id} (game={game_id})")
        if away_db_id not in db_to_app_team_id:
            raise ValueError(f"Unmapped away_team_id: {away_db_id} (game={game_id})")

        scheduled_at_kst = parse_datetime(row.get("scheduled_at"), "scheduled_at")
        status_code, status_text = map_status(row)
        inning_state = str(row.get("inning_state") or "").strip()

        game: dict[str, Any] = {
            "id": game_id,
            "scheduled_start": scheduled_at_kst.isoformat(timespec="seconds"),
            "venue": str(row.get("stadium") or "").strip(),
            "away_team_id": db_to_app_team_id[away_db_id],
            "home_team_id": db_to_app_team_id[home_db_id],
            "away_score": as_int_or_none(row.get("away_score")),
            "home_score": as_int_or_none(row.get("home_score")),
            "status_code": status_code,
            "status_text": status_text,
            "events": [],
            "note": f"db_export provider_game_id={row.get('provider_game_id')}",
        }

        if inning_state:
            game["inning_text"] = inning_state
        elif status_code == "FINAL":
            game["inning_text"] = "종료"

        if not game["venue"]:
            game["venue"] = str(row.get("stadium_code") or "장소 미정")

        converted.append(game)

    return converted


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert DB-exported games.json + teams.json to app bootstrap JSON schema."
    )
    parser.add_argument("--games", type=Path, required=True, help="Path to DB-exported games.json")
    parser.add_argument("--teams", type=Path, required=True, help="Path to DB-exported teams.json")
    parser.add_argument("--output", type=Path, required=True, help="Output path for app bootstrap JSON")
    args = parser.parse_args()

    team_rows = load_json_list(args.teams, "teams.json")
    game_rows = load_json_list(args.games, "games.json")

    teams, db_to_app = convert_teams(team_rows)
    games = convert_games(game_rows, db_to_app)

    bootstrap = {
        "teams": teams,
        "games": games,
        "notifications": [],
        "settings": None,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(bootstrap, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote bootstrap: {args.output}")
    print(f"teams={len(teams)} games={len(games)} notifications=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
