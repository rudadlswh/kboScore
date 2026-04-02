from __future__ import annotations

import calendar
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.repositories.game_repository import GameRepository
from app.schemas.game import GameStatus
from app.schemas.schedule import ScheduleMonthGameItem, ScheduleMonthResponse, ScheduleMonthTeam
from app.services.game_query_service import GameQueryService


router = APIRouter()
game_repository = GameRepository()


@router.get(
    "/schedule/month",
    response_model=ScheduleMonthResponse,
    summary="List month schedule for app bootstrap and calendar views",
)
def get_month_schedule(
    db: Session = Depends(get_db),
    year: int = Query(..., ge=2000, le=2100),
    month: int = Query(..., ge=1, le=12),
) -> ScheduleMonthResponse:
    date_from = date(year, month, 1)
    date_to = date(year, month, calendar.monthrange(year, month)[1])

    rows = game_repository.list_games_in_range(
        db,
        date_from=date_from,
        date_to=date_to,
    )
    items = [
        ScheduleMonthGameItem(
            game_id=row["game_id"],
            scheduled_at=row["scheduled_at"],
            status=GameQueryService._normalize_status(row["status"], row.get("is_postponed"), row.get("is_cancelled")),
            season_classification=GameQueryService._normalize_season_classification(row.get("season_classification")),
            stadium=row["stadium_name_ko"],
            home_team=ScheduleMonthTeam(
                team_id=row["home_team_id"],
                name_ko=row["home_team_name_ko"],
                short_name=row["home_team_short_name"],
            ),
            away_team=ScheduleMonthTeam(
                team_id=row["away_team_id"],
                name_ko=row["away_team_name_ko"],
                short_name=row["away_team_short_name"],
            ),
            home_score=row["home_score"],
            away_score=row["away_score"],
            inning_state=row["inning_state"],
        )
        for row in rows
    ]

    return ScheduleMonthResponse(
        year=year,
        month=month,
        total_count=len(items),
        games=items,
    )
