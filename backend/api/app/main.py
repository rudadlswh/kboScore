from fastapi import FastAPI

from app.api.routes.games import router as games_router
from app.api.routes.health import router as health_router
from app.api.routes.schedule import router as schedule_router
from app.api.routes.standings import router as standings_router
from app.api.routes.teams import router as teams_router


app = FastAPI(title="KBO Read API", version="1.0.0")

app.include_router(health_router, prefix="/v1", tags=["health"])
app.include_router(teams_router, prefix="/v1", tags=["teams"])
app.include_router(games_router, prefix="/v1", tags=["games"])
app.include_router(schedule_router, prefix="/v1", tags=["schedule"])
app.include_router(standings_router, prefix="/v1", tags=["standings"])
