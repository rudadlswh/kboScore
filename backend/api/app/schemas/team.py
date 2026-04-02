from __future__ import annotations

from app.schemas.common import ApiModel


class TeamResponse(ApiModel):
    team_id: str
    name_ko: str
    name_en: str | None = None
    short_name: str


class TeamSummary(ApiModel):
    team_id: str
    name_ko: str


class TeamListResponse(ApiModel):
    teams: list[TeamResponse]
