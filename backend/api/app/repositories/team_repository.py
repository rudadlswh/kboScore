from __future__ import annotations

from collections.abc import Sequence

from sqlalchemy import text
from sqlalchemy.orm import Session


class TeamRepository:
    def list_teams(self, db: Session) -> Sequence[dict]:
        result = db.execute(
            text(
                """
                SELECT
                    code AS team_id,
                    name_ko,
                    name_en,
                    short_name
                FROM teams
                WHERE is_active = TRUE
                ORDER BY sort_order ASC, code ASC
                """
            )
        )
        return result.mappings().all()

    def list_bootstrap_teams(self, db: Session) -> Sequence[dict]:
        result = db.execute(
            text(
                """
                SELECT
                    code AS team_code,
                    name_ko,
                    name_en,
                    short_name,
                    sort_order
                FROM teams
                WHERE is_active = TRUE
                ORDER BY sort_order ASC, code ASC
                """
            )
        )
        return result.mappings().all()

    def list_teams_with_ranking_metadata(self, db: Session) -> Sequence[dict]:
        result = db.execute(
            text(
                """
                SELECT
                    code AS team_id,
                    name_ko,
                    name_en,
                    short_name,
                    sort_order,
                    previous_regular_season_rank
                FROM teams
                WHERE is_active = TRUE
                ORDER BY sort_order ASC, code ASC
                """
            )
        )
        return result.mappings().all()

    def get_team_by_code(self, db: Session, team_id: str) -> dict | None:
        result = db.execute(
            text(
                """
                SELECT
                    code AS team_id,
                    name_ko,
                    name_en,
                    short_name
                FROM teams
                WHERE code = :team_id
                  AND is_active = TRUE
                LIMIT 1
                """
            ),
            {"team_id": team_id},
        )
        return result.mappings().first()
