from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.repositories.game_repository import GameRepository
from app.repositories.team_repository import TeamRepository
from app.schemas.common import ErrorDetail, ErrorResponse
from app.schemas.game import GameStatus, StadiumSummary, TeamGameItem, TeamGameScore, TeamGamesResponse
from app.schemas.team import TeamListResponse, TeamResponse, TeamSummary
from app.services.game_query_service import GameQueryService


router = APIRouter()
team_repository = TeamRepository()
game_query_service = GameQueryService(
    game_repository=GameRepository(),
    snapshot_repository=None,  # type: ignore[arg-type]
    weather_repository=None,  # type: ignore[arg-type]
)
TEAMS_EXAMPLE = {
    "teams": [
        {
            "teamId": "LG",
            "nameKo": "LG 트윈스",
            "nameEn": "LG Twins",
            "shortName": "LG",
        }
    ]
}
TEAM_NOT_FOUND_EXAMPLE = {
    "error": {
        "code": "TEAM_NOT_FOUND",
        "message": "Team not found",
        "details": None,
    }
}
TEAM_NOT_FOUND_RESPONSE = {
    "model": ErrorResponse,
    "description": "The requested team does not exist.",
    "content": {"application/json": {"example": TEAM_NOT_FOUND_EXAMPLE}},
}
TEAM_GAMES_EXAMPLE = {
    "teamId": "LG",
    "dateFrom": "2026-03-28",
    "dateTo": "2026-03-30",
    "games": [
        {
            "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
            "scheduledAt": "2026-03-28T14:00:00+09:00",
            "opponentTeam": {"teamId": "DOO", "nameKo": "두산 베어스"},
            "isHome": False,
            "status": "live",
            "seasonClassification": "regular_season",
            "score": {"myTeam": 5, "opponent": 3},
            "inningState": "7회초",
            "stadium": {"stadiumId": "JS", "nameKo": "잠실"},
        }
    ],
}


def _error_response(status_code: int, code: str, message: str, details: Any = None) -> JSONResponse:
    payload = ErrorResponse(error=ErrorDetail(code=code, message=message, details=details))
    return JSONResponse(status_code=status_code, content=payload.model_dump(by_alias=True))


def _team_not_found_response() -> JSONResponse:
    return _error_response(404, "TEAM_NOT_FOUND", "Team not found")


@router.get(
    "/teams",
    response_model=TeamListResponse,
    summary="List teams",
    responses={
        200: {
            "description": "Active KBO teams ordered for display.",
            "content": {"application/json": {"example": TEAMS_EXAMPLE}},
        }
    },
)
def get_teams(db: Annotated[Session, Depends(get_db)]) -> TeamListResponse:
    rows = team_repository.list_teams(db)
    return TeamListResponse(
        teams=[
            TeamResponse(
                team_id=row["team_id"],
                name_ko=row["name_ko"],
                name_en=row["name_en"],
                short_name=row["short_name"],
            )
            for row in rows
        ]
    )


@router.get(
    "/teams/{team_id}/games",
    response_model=TeamGamesResponse,
    summary="List games for a team within a date range",
    responses={
        200: {
            "description": "Games where the team appears as either home or away.",
            "content": {"application/json": {"example": TEAM_GAMES_EXAMPLE}},
        },
        404: TEAM_NOT_FOUND_RESPONSE,
    },
)
def get_team_games(
    team_id: str,
    db: Annotated[Session, Depends(get_db)],
    date_from: date = Query(
        ...,
        alias="dateFrom",
        description="Inclusive KST calendar start date in YYYY-MM-DD format.",
    ),
    date_to: date = Query(
        ...,
        alias="dateTo",
        description="Inclusive KST calendar end date in YYYY-MM-DD format.",
    ),
    status: GameStatus | None = Query(
        default=None,
        description="Optional canonical game status filter.",
    ),
) -> TeamGamesResponse | JSONResponse:
    normalized_team_id = team_id.strip().upper()
    team_row = team_repository.get_team_by_code(db, normalized_team_id)
    if team_row is None:
        return _team_not_found_response()

    rows = game_query_service.list_team_games(
        db,
        team_id=normalized_team_id,
        date_from=date_from,
        date_to=date_to,
        status=status,
    )
    return TeamGamesResponse(
        team_id=normalized_team_id,
        date_from=date_from,
        date_to=date_to,
        games=[
            TeamGameItem(
                game_id=row["game_id"],
                scheduled_at=row["scheduled_at"],
                opponent_team=TeamSummary(
                    team_id=row["opponent_team_id"],
                    name_ko=row["opponent_team_name_ko"],
                ),
                is_home=bool(row["is_home"]),
                status=GameQueryService._normalize_status(row["status"]),
                season_classification=GameQueryService._normalize_season_classification(
                    row.get("season_classification")
                ),
                score=TeamGameScore(
                    my_team=row["my_team_score"],
                    opponent=row["opponent_score"],
                ),
                inning_state=row["inning_state"],
                stadium=StadiumSummary(
                    stadium_id=row["stadium_id"],
                    name_ko=row["stadium_name_ko"],
                ),
            )
            for row in rows
        ],
    )
