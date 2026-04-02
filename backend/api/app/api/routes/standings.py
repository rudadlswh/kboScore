from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.repositories.game_repository import GameRepository
from app.repositories.team_repository import TeamRepository
from app.schemas.standings import StandingsResponse
from app.services.postseason_qualification_probability_service import PostseasonQualificationProbabilityService
from app.services.regular_season_ranking_service import RegularSeasonRankingService
from app.services.regular_season_record_service import RegularSeasonRecordService
from app.services.standings_query_service import StandingsQueryService


KST = timezone(timedelta(hours=9))

router = APIRouter()
standings_query_service = StandingsQueryService(
    team_repository=TeamRepository(),
    game_repository=GameRepository(),
    record_service=RegularSeasonRecordService(),
    ranking_service=RegularSeasonRankingService(),
    probability_service=PostseasonQualificationProbabilityService(
        record_service=RegularSeasonRecordService(),
        ranking_service=RegularSeasonRankingService(),
    ),
)


@router.get(
    "/standings",
    response_model=StandingsResponse,
    summary="Get regular-season standings using KBO ranking rules",
)
def get_regular_season_standings(
    db: Session = Depends(get_db),
    season_id: int | None = Query(
        default=None,
        alias="seasonId",
        ge=2000,
        le=2100,
    ),
) -> StandingsResponse:
    resolved_season_id = season_id or datetime.now(tz=KST).year
    return standings_query_service.get_regular_season_standings(db, season_id=resolved_season_id)
