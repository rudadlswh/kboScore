from fastapi import APIRouter

from app.schemas.common import HealthResponse


router = APIRouter()
HEALTH_EXAMPLE = {"status": "ok"}


@router.get(
    "/health",
    response_model=HealthResponse,
    summary="Health check",
    responses={
        200: {
            "description": "API process is healthy.",
            "content": {"application/json": {"example": HEALTH_EXAMPLE}},
        }
    },
)
def get_health() -> HealthResponse:
    return HealthResponse(status="ok")
