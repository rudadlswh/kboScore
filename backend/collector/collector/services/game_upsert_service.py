from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

import psycopg

from collector.models.live_models import NormalizedLiveGameState
from collector.models.schedule_models import NormalizedScheduleGame


@dataclass(frozen=True, slots=True)
class BootstrapUpsertResult:
    action: Literal["inserted", "updated", "unchanged"]
    game_id: str


@dataclass(slots=True)
class GameUpsertService:
    conn: psycopg.Connection

    def upsert_bootstrap_game(
        self,
        game: NormalizedScheduleGame,
        home_team_id: str,
        away_team_id: str,
        observed_at: datetime,
    ) -> BootstrapUpsertResult:
        """Insert or update a bootstrap game while keeping provider_game_id immutable."""
        existing = self._find_existing_game(
            game=game,
            home_team_id=home_team_id,
            away_team_id=away_team_id,
        )
        is_postponed, is_cancelled = self._status_flags(game.status)

        if existing is None:
            with self.conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO games (
                        provider,
                        provider_game_id,
                        game_date,
                        scheduled_at,
                        stadium,
                        stadium_code,
                        status,
                        home_team_id,
                        away_team_id,
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
                        %(status)s,
                        %(home_team_id)s,
                        %(away_team_id)s,
                        %(is_cancelled)s,
                        %(is_postponed)s,
                        %(source_updated_at)s,
                        %(official_provider_game_id)s,
                        %(provider_game_id_kind)s
                    )
                    RETURNING id::text AS id
                    """,
                    {
                        "provider": game.provider,
                        "provider_game_id": game.provider_game_id,
                        "game_date": game.game_date,
                        "scheduled_at": game.scheduled_at,
                        "stadium": game.stadium,
                        "stadium_code": game.stadium_code,
                        "status": game.status,
                        "home_team_id": home_team_id,
                        "away_team_id": away_team_id,
                        "is_cancelled": is_cancelled,
                        "is_postponed": is_postponed,
                        "source_updated_at": observed_at,
                        "official_provider_game_id": game.official_provider_game_id,
                        "provider_game_id_kind": game.provider_game_id_kind,
                    },
                )
                inserted = cur.fetchone()
            return BootstrapUpsertResult(action="inserted", game_id=str(inserted["id"]))

        next_official_provider_game_id = existing["official_provider_game_id"] or game.official_provider_game_id
        next_values = {
            "official_provider_game_id": next_official_provider_game_id,
            "game_date": game.game_date,
            "scheduled_at": game.scheduled_at,
            "stadium": game.stadium,
            "stadium_code": game.stadium_code,
            "status": game.status,
            "home_team_id": home_team_id,
            "away_team_id": away_team_id,
            "is_postponed": is_postponed,
            "is_cancelled": is_cancelled,
        }

        changed = any(existing[field] != value for field, value in next_values.items())
        if not changed:
            return BootstrapUpsertResult(action="unchanged", game_id=str(existing["id"]))

        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE games
                SET
                    official_provider_game_id = %(official_provider_game_id)s,
                    game_date = %(game_date)s,
                    scheduled_at = %(scheduled_at)s,
                    stadium = %(stadium)s,
                    stadium_code = %(stadium_code)s,
                    status = %(status)s,
                    home_team_id = %(home_team_id)s::uuid,
                    away_team_id = %(away_team_id)s::uuid,
                    is_postponed = %(is_postponed)s,
                    is_cancelled = %(is_cancelled)s,
                    source_updated_at = %(source_updated_at)s
                WHERE id = %(game_id)s::uuid
                """,
                {
                    **next_values,
                    "source_updated_at": observed_at,
                    "game_id": existing["id"],
                },
            )
        return BootstrapUpsertResult(action="updated", game_id=str(existing["id"]))

    def apply_live_game_update(
        self,
        game_id: str,
        live_state: NormalizedLiveGameState,
        observed_at: datetime,
    ) -> bool:
        """Apply source-driven live updates to the canonical games row."""
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id::text AS id,
                    status,
                    inning_state,
                    home_score,
                    away_score
                FROM games
                WHERE id = %s::uuid
                LIMIT 1
                """,
                (game_id,),
            )
            existing = cur.fetchone()

        if existing is None:
            raise ValueError(f"Game not found for live update: {game_id}")

        next_status = self._next_live_status(existing["status"], live_state)
        next_inning_state = live_state.inning_state
        next_home_score = live_state.home_score
        next_away_score = live_state.away_score

        changed = any(
            [
                existing["status"] != next_status,
                existing["inning_state"] != next_inning_state,
                existing["home_score"] != next_home_score,
                existing["away_score"] != next_away_score,
            ]
        )
        if not changed:
            return False

        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE games
                SET
                    status = %(status)s,
                    inning_state = %(inning_state)s,
                    home_score = %(home_score)s,
                    away_score = %(away_score)s,
                    source_updated_at = %(source_updated_at)s
                WHERE id = %(game_id)s::uuid
                """,
                {
                    "status": next_status,
                    "inning_state": next_inning_state,
                    "home_score": next_home_score,
                    "away_score": next_away_score,
                    "source_updated_at": observed_at,
                    "game_id": game_id,
                },
            )
        return True

    def mark_game_postponed(
        self,
        game_id: str,
        observed_at: datetime,
    ) -> bool:
        """Set status=postponed, is_postponed=true, is_cancelled=false, and source_updated_at."""
        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE games
                SET
                    status = 'postponed',
                    is_postponed = TRUE,
                    is_cancelled = FALSE,
                    source_updated_at = %s
                WHERE id = %s::uuid
                  AND (
                    status IS DISTINCT FROM 'postponed'
                    OR is_postponed IS DISTINCT FROM TRUE
                    OR is_cancelled IS DISTINCT FROM FALSE
                  )
                RETURNING id::text AS id
                """,
                (observed_at, game_id),
            )
            row = cur.fetchone()
        return row is not None

    def _find_existing_game(
        self,
        *,
        game: NormalizedScheduleGame,
        home_team_id: str,
        away_team_id: str,
    ) -> dict | None:
        select_sql = """
            SELECT
                id::text AS id,
                provider,
                provider_game_id,
                official_provider_game_id,
                game_date,
                scheduled_at,
                stadium,
                stadium_code,
                status,
                home_team_id::text AS home_team_id,
                away_team_id::text AS away_team_id,
                is_postponed,
                is_cancelled
            FROM games
        """

        with self.conn.cursor() as cur:
            cur.execute(
                select_sql
                + """
                WHERE provider = %s
                  AND provider_game_id = %s
                LIMIT 1
                """,
                (game.provider, game.provider_game_id),
            )
            row = cur.fetchone()
            if row is not None:
                return row

            if game.official_provider_game_id:
                cur.execute(
                    select_sql
                    + """
                    WHERE provider = %s
                      AND official_provider_game_id = %s
                    LIMIT 1
                    """,
                    (game.provider, game.official_provider_game_id),
                )
                row = cur.fetchone()
                if row is not None:
                    return row

            cur.execute(
                select_sql
                + """
                WHERE provider = %s
                  AND game_date = %s
                  AND home_team_id = %s::uuid
                  AND away_team_id = %s::uuid
                  AND scheduled_at IS NOT DISTINCT FROM %s
                  AND stadium IS NOT DISTINCT FROM %s
                  AND stadium_code IS NOT DISTINCT FROM %s
                LIMIT 1
                """,
                (
                    game.provider,
                    game.game_date,
                    home_team_id,
                    away_team_id,
                    game.scheduled_at,
                    game.stadium,
                    game.stadium_code,
                ),
            )
            return cur.fetchone()

    @staticmethod
    def _status_flags(status: str) -> tuple[bool, bool]:
        if status == "postponed":
            return True, False
        if status == "cancelled":
            return False, True
        return False, False

    @staticmethod
    def _next_live_status(current_status: str, live_state: NormalizedLiveGameState) -> str:
        if live_state.is_postponed():
            return "postponed"
        if live_state.is_final():
            return "finished"
        if live_state.is_live():
            return "live"
        if live_state.is_pregame():
            if current_status in {"live", "postponed", "finished", "cancelled"}:
                return current_status
            return "scheduled"
        return current_status
