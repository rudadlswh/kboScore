from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.repositories.event_repository import EventRepository
from app.repositories.game_repository import GameRepository
from app.repositories.snapshot_repository import SnapshotRepository
from app.repositories.weather_repository import WeatherRepository
from app.schemas.common import ErrorDetail, ErrorResponse
from app.schemas.event import EventsFeedResponse, GameEventsResponse, GameEventType
from app.schemas.game import GameDetailResponse, GameSnapshotsResponse, GameStatus, GamesResponse
from app.schemas.weather import GameWeatherResponse
from app.services.game_query_service import GameQueryService


router = APIRouter()
game_query_service = GameQueryService(
    game_repository=GameRepository(),
    snapshot_repository=SnapshotRepository(),
    weather_repository=WeatherRepository(),
    event_repository=EventRepository(),
)
GAME_NOT_FOUND_EXAMPLE = {
    "error": {
        "code": "GAME_NOT_FOUND",
        "message": "Game not found",
        "details": None,
    }
}
GAME_NOT_FOUND_RESPONSE = {
    "model": ErrorResponse,
    "description": "The requested game does not exist.",
    "content": {"application/json": {"example": GAME_NOT_FOUND_EXAMPLE}},
}
GAMES_RESPONSE_EXAMPLE = {
    "date": "2026-03-28",
    "games": [
        {
            "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
            "scheduledAt": "2026-03-28T14:00:00+09:00",
            "homeTeam": {"teamId": "DOO", "nameKo": "두산 베어스"},
            "awayTeam": {"teamId": "LG", "nameKo": "LG 트윈스"},
            "stadium": {"stadiumId": "JS", "nameKo": "잠실"},
            "status": "live",
            "seasonClassification": "regular_season",
            "score": {"home": 3, "away": 5},
            "inningState": "7회초",
            "isDoubleHeader": False,
            "isPostponed": False,
        }
    ],
}
GAME_DETAIL_EXAMPLE = {
    "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
    "providerGameId": "20260328LGDOO0",
    "officialProviderGameId": "20260328LGDOO1",
    "scheduledAt": "2026-03-28T14:00:00+09:00",
    "homeTeam": {"teamId": "DOO", "nameKo": "두산 베어스"},
    "awayTeam": {"teamId": "LG", "nameKo": "LG 트윈스"},
    "stadium": {"stadiumId": "JS", "nameKo": "잠실"},
    "status": "live",
    "seasonClassification": "regular_season",
    "score": {"home": 3, "away": 5},
    "inningState": "7회초",
    "latestSnapshotAt": "2026-03-28T16:11:20+09:00",
    "weather": {
        "temperatureC": 12.4,
        "condition": "흐림",
        "precipitationMm": 0.2,
        "observedAt": "2026-03-28T16:00:00+09:00",
    },
}
SNAPSHOTS_RESPONSE_EXAMPLE = {
    "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
    "snapshots": [
        {
            "snapshotAt": "2026-03-28T15:10:00+09:00",
            "status": "live",
            "score": {"home": 0, "away": 1},
            "inningState": "2회초",
        }
    ],
}
WEATHER_RESPONSE_EXAMPLE = {
    "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
    "stadiumId": "JS",
    "current": {
        "temperatureC": 12.4,
        "condition": "흐림",
        "precipitationMm": 0.2,
        "observedAt": "2026-03-28T16:00:00+09:00",
    },
}
GAME_EVENTS_RESPONSE_EXAMPLE = {
    "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
    "events": [
        {
            "eventType": "postponed_confirmed",
            "confirmed": True,
            "reason": "rain",
            "recordedAt": "2026-03-28T13:20:00+09:00",
        }
    ],
}
EVENTS_FEED_RESPONSE_EXAMPLE = {
    "date": "2026-03-28",
    "events": [
        {
            "gameId": "c4f7b1dd-76c7-4a42-8e7f-1f85370c0f6a",
            "eventType": "postponed_confirmed",
            "confirmed": True,
            "reason": "rain",
            "recordedAt": "2026-03-28T13:20:00+09:00",
        }
    ],
}
KST = timezone(timedelta(hours=9))


def _error_response(status_code: int, code: str, message: str, details: Any = None) -> JSONResponse:
    payload = ErrorResponse(error=ErrorDetail(code=code, message=message, details=details))
    return JSONResponse(status_code=status_code, content=payload.model_dump(by_alias=True))


def _game_not_found_response() -> JSONResponse:
    return _error_response(404, "GAME_NOT_FOUND", "Game not found")


@router.get(
    "/games",
    response_model=GamesResponse,
    summary="List games by KST date",
    responses={
        200: {
            "description": "Canonical game rows for the requested KST calendar date.",
            "content": {"application/json": {"example": GAMES_RESPONSE_EXAMPLE}},
        }
    },
)
def get_games(
    db: Annotated[Session, Depends(get_db)],
    date_value: date | None = Query(
        default=None,
        alias="date",
        description="KST calendar date to query, in YYYY-MM-DD format. Defaults to the current KST date.",
        examples=["2026-03-28"],
    ),
    team_id: str | None = Query(
        default=None,
        alias="teamId",
        description="Optional public team code filter. Maps to teams.code, for example LG or DOO.",
    ),
    status: GameStatus | None = Query(
        default=None,
        description="Optional canonical game status filter.",
    ),
) -> GamesResponse:
    resolved_date = date_value or datetime.now(tz=KST).date()
    return game_query_service.list_games(db, game_date=resolved_date, team_id=team_id, status=status)


@router.get(
    "/games/{game_id}",
    response_model=GameDetailResponse,
    summary="Get game detail",
    responses={
        200: {
            "description": "Canonical game detail with latest snapshot timestamp and latest stadium weather.",
            "content": {"application/json": {"example": GAME_DETAIL_EXAMPLE}},
        },
        404: GAME_NOT_FOUND_RESPONSE,
    },
)
def get_game_detail(
    game_id: str,
    db: Annotated[Session, Depends(get_db)],
) -> GameDetailResponse | JSONResponse:
    response = game_query_service.get_game_detail(db, game_id)
    if response is None:
        return _game_not_found_response()
    return response


@router.get(
    "/games/{game_id}/snapshots",
    response_model=GameSnapshotsResponse,
    summary="List game snapshots",
    responses={
        200: {
            "description": "Latest game snapshots ordered by snapshot time descending.",
            "content": {"application/json": {"example": SNAPSHOTS_RESPONSE_EXAMPLE}},
        },
        404: GAME_NOT_FOUND_RESPONSE,
    },
)
def get_game_snapshots(
    game_id: str,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(
        default=50,
        ge=1,
        le=200,
        description="Maximum number of snapshots to return. Ordered by snapshotAt descending.",
    ),
) -> GameSnapshotsResponse | JSONResponse:
    response = game_query_service.get_game_snapshots(db, game_id, limit=limit)
    if response is None:
        return _game_not_found_response()
    return response


@router.get(
    "/games/{game_id}/weather",
    response_model=GameWeatherResponse,
    summary="Get latest stadium weather for a game",
    responses={
        200: {
            "description": "Latest weather row for the game's stadium.",
            "content": {"application/json": {"example": WEATHER_RESPONSE_EXAMPLE}},
        },
        404: GAME_NOT_FOUND_RESPONSE,
    },
)
def get_game_weather(
    game_id: str,
    db: Annotated[Session, Depends(get_db)],
) -> GameWeatherResponse | JSONResponse:
    response = game_query_service.get_game_weather(db, game_id)
    if response is None:
        return _game_not_found_response()
    return response


@router.get(
    "/games/{game_id}/events",
    response_model=GameEventsResponse,
    summary="List canonical event history for a game",
    responses={
        200: {
            "description": "Append-only canonical event history for the game.",
            "content": {"application/json": {"example": GAME_EVENTS_RESPONSE_EXAMPLE}},
        },
        404: GAME_NOT_FOUND_RESPONSE,
    },
)
def get_game_events(
    game_id: str,
    db: Annotated[Session, Depends(get_db)],
) -> GameEventsResponse | JSONResponse:
    response = game_query_service.get_game_events(db, game_id)
    if response is None:
        return _game_not_found_response()
    return response


@router.get(
    "/events",
    response_model=EventsFeedResponse,
    summary="List canonical event feed for a KST date",
    responses={
        200: {
            "description": "Canonical event feed filtered by KST date and optional team/event type filters.",
            "content": {"application/json": {"example": EVENTS_FEED_RESPONSE_EXAMPLE}},
        }
    },
)
def get_events(
    db: Annotated[Session, Depends(get_db)],
    date_value: date = Query(
        ...,
        alias="date",
        description="KST calendar date for event feed filtering, in YYYY-MM-DD format.",
    ),
    team_id: str | None = Query(
        default=None,
        alias="teamId",
        description="Optional public team code filter. Matches games where the team is home or away.",
    ),
    event_type: GameEventType | None = Query(
        default=None,
        alias="eventType",
        description="Optional canonical event type filter.",
    ),
) -> EventsFeedResponse:
    return game_query_service.list_events(
        db,
        event_date=date_value,
        team_id=team_id,
        event_type=event_type,
    )
