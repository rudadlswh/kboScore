from __future__ import annotations

from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, field_serializer


KST = ZoneInfo("Asia/Seoul")


def to_camel(value: str) -> str:
    parts = value.split("_")
    return parts[0] + "".join(part.capitalize() for part in parts[1:])


def serialize_datetime_to_kst(value: datetime) -> str:
    if value.tzinfo is None:
        return value.replace(tzinfo=KST).isoformat()
    return value.astimezone(KST).isoformat()


class ApiModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, alias_generator=to_camel)

    @field_serializer("*", when_used="json", check_fields=False)
    def serialize_datetime_fields(self, value: Any) -> Any:
        if isinstance(value, datetime):
            return serialize_datetime_to_kst(value)
        return value


class HealthResponse(ApiModel):
    status: str


class ErrorDetail(ApiModel):
    code: str
    message: str
    details: Any | None = None


class ErrorResponse(ApiModel):
    error: ErrorDetail
