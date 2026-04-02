from __future__ import annotations

from collections.abc import Sequence
from datetime import date

from sqlalchemy import text
from sqlalchemy.orm import Session


class GameRepository:
    _BASE_GAME_SELECT = """
        SELECT
            g.id::text AS game_id,
            g.provider_game_id,
            g.official_provider_game_id,
            g.game_date,
            g.scheduled_at,
            home.code AS home_team_id,
            home.name_ko AS home_team_name_ko,
            home.short_name AS home_team_short_name,
            away.code AS away_team_id,
            away.name_ko AS away_team_name_ko,
            away.short_name AS away_team_short_name,
            g.stadium_code AS stadium_id,
            g.stadium AS stadium_name_ko,
            g.status,
            g.season_classification,
            g.home_score,
            g.away_score,
            g.inning_state,
            latest_snapshot.status AS latest_snapshot_status,
            latest_snapshot.home_score AS latest_snapshot_home_score,
            latest_snapshot.away_score AS latest_snapshot_away_score,
            latest_snapshot.inning_state AS latest_snapshot_inning_state,
            FALSE AS is_double_header,
            g.is_postponed,
            g.is_cancelled
        FROM games g
        JOIN teams home ON home.id = g.home_team_id
        JOIN teams away ON away.id = g.away_team_id
        LEFT JOIN LATERAL (
            SELECT
                gs.status,
                gs.home_score,
                gs.away_score,
                gs.inning_state
            FROM game_snapshots gs
            WHERE gs.game_id = g.id
            ORDER BY gs.snapshot_at DESC
            LIMIT 1
        ) latest_snapshot ON TRUE
    """

    def list_games(
        self,
        db: Session,
        *,
        game_date: date,
        team_id: str | None = None,
        status: str | None = None,
    ) -> Sequence[dict]:
        # The collector already persists game_date in KST, so the read API can
        # filter by the canonical game_date column directly.
        query = f"""
            {self._BASE_GAME_SELECT}
            WHERE g.game_date = :game_date
        """
        params: dict[str, object] = {"game_date": game_date}

        if team_id:
            query += """
                AND (
                    home.code = :team_id
                    OR away.code = :team_id
                )
            """
            params["team_id"] = team_id

        if status:
            query += " AND g.status = :status"
            params["status"] = status

        query += """
            ORDER BY
                g.scheduled_at ASC NULLS LAST,
                away.sort_order ASC,
                home.sort_order ASC,
                g.id ASC
        """

        result = db.execute(text(query), params)
        return result.mappings().all()

    def list_games_in_range(
        self,
        db: Session,
        *,
        date_from: date,
        date_to: date,
        season_classification: str | None = None,
    ) -> Sequence[dict]:
        query = f"""
            {self._BASE_GAME_SELECT}
            WHERE g.game_date >= :date_from
              AND g.game_date <= :date_to
        """
        params: dict[str, object] = {
            "date_from": date_from,
            "date_to": date_to,
        }
        if season_classification is not None:
            query += " AND g.season_classification = :season_classification"
            params["season_classification"] = season_classification

        query += """
            ORDER BY
                g.game_date ASC,
                g.scheduled_at ASC NULLS LAST,
                away.sort_order ASC,
                home.sort_order ASC,
                g.id ASC
        """
        result = db.execute(text(query), params)
        return result.mappings().all()

    def get_game_detail_base(self, db: Session, game_id: str) -> dict | None:
        result = db.execute(
            text(
                """
                SELECT
                    -- Public gameId currently maps to the canonical games.id UUID text.
                    g.id::text AS game_id,
                    g.provider_game_id,
                    g.official_provider_game_id,
                    g.scheduled_at,
                    home.code AS home_team_id,
                    home.name_ko AS home_team_name_ko,
                    away.code AS away_team_id,
                    away.name_ko AS away_team_name_ko,
                    -- Public stadiumId currently maps to collector-managed stadium_code.
                    g.stadium_code AS stadium_id,
                    g.stadium AS stadium_name_ko,
                    g.status,
                    g.season_classification,
                    g.home_score,
                    g.away_score,
                    g.inning_state,
                    latest_snapshot.status AS latest_snapshot_status,
                    latest_snapshot.home_score AS latest_snapshot_home_score,
                    latest_snapshot.away_score AS latest_snapshot_away_score,
                    latest_snapshot.inning_state AS latest_snapshot_inning_state,
                    FALSE AS is_double_header,
                    g.is_postponed,
                    g.is_cancelled,
                    latest_snapshot.snapshot_at AS latest_snapshot_at
                FROM games g
                JOIN teams home ON home.id = g.home_team_id
                JOIN teams away ON away.id = g.away_team_id
                LEFT JOIN LATERAL (
                    SELECT
                        snapshot_at,
                        status,
                        home_score,
                        away_score,
                        inning_state
                    FROM game_snapshots
                    WHERE game_id = g.id
                    ORDER BY snapshot_at DESC
                    LIMIT 1
                ) latest_snapshot ON TRUE
                WHERE g.id::text = :game_id
                LIMIT 1
                """
            ),
            {"game_id": game_id},
        )
        return result.mappings().first()

    def get_game_lookup(self, db: Session, game_id: str) -> dict | None:
        result = db.execute(
            text(
                """
                SELECT
                    -- Public gameId currently maps to the canonical games.id UUID text.
                    g.id::text AS game_id,
                    -- Public stadiumId currently maps to collector-managed stadium_code.
                    g.stadium_code AS stadium_id
                FROM games g
                WHERE g.id::text = :game_id
                LIMIT 1
                """
            ),
            {"game_id": game_id},
        )
        return result.mappings().first()

    def list_team_games(
        self,
        db: Session,
        *,
        team_id: str,
        date_from: date,
        date_to: date,
        status: str | None = None,
    ) -> Sequence[dict]:
        query = """
            SELECT
                g.id::text AS game_id,
                g.scheduled_at,
                g.stadium_code AS stadium_id,
                g.stadium AS stadium_name_ko,
                g.status,
                g.season_classification,
                g.home_score,
                g.away_score,
                g.inning_state,
                g.is_postponed,
                g.is_cancelled,
                latest_snapshot.status AS latest_snapshot_status,
                latest_snapshot.home_score AS latest_snapshot_home_score,
                latest_snapshot.away_score AS latest_snapshot_away_score,
                latest_snapshot.inning_state AS latest_snapshot_inning_state,
                home.code AS home_team_id,
                home.name_ko AS home_team_name_ko,
                away.code AS away_team_id,
                away.name_ko AS away_team_name_ko,
                CASE WHEN home.code = :team_id THEN TRUE ELSE FALSE END AS is_home,
                CASE
                    WHEN home.code = :team_id THEN away.code
                    ELSE home.code
                END AS opponent_team_id,
                CASE
                    WHEN home.code = :team_id THEN away.name_ko
                    ELSE home.name_ko
                END AS opponent_team_name_ko,
                CASE
                    WHEN home.code = :team_id THEN g.home_score
                    ELSE g.away_score
                END AS my_team_score,
                CASE
                    WHEN home.code = :team_id THEN g.away_score
                    ELSE g.home_score
                END AS opponent_score
            FROM games g
            JOIN teams home ON home.id = g.home_team_id
            JOIN teams away ON away.id = g.away_team_id
            LEFT JOIN LATERAL (
                SELECT
                    gs.status,
                    gs.home_score,
                    gs.away_score,
                    gs.inning_state
                FROM game_snapshots gs
                WHERE gs.game_id = g.id
                ORDER BY gs.snapshot_at DESC
                LIMIT 1
            ) latest_snapshot ON TRUE
            WHERE g.game_date >= :date_from
              AND g.game_date <= :date_to
              AND (
                home.code = :team_id
                OR away.code = :team_id
              )
        """
        params: dict[str, object] = {
            "team_id": team_id,
            "date_from": date_from,
            "date_to": date_to,
        }

        if status:
            query += " AND g.status = :status"
            params["status"] = status

        query += """
            ORDER BY
                g.game_date ASC,
                g.scheduled_at ASC NULLS LAST,
                g.id ASC
        """

        result = db.execute(text(query), params)
        return result.mappings().all()
