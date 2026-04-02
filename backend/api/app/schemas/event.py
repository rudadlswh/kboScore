from __future__ import annotations

from datetime import date, datetime
from enum import StrEnum

from app.schemas.common import ApiModel


class GameEventType(StrEnum):
    POSTPONED_CANDIDATE = "postponed_candidate"
    POSTPONED_CONFIRMED = "postponed_confirmed"
    DOUBLEHEADER_ANNOUNCED = "doubleheader_announced"
    MAKEUP_SCHEDULED = "makeup_scheduled"
    VENUE_CHANGED = "venue_changed"
    TIME_CHANGED = "time_changed"
    STATUS_CORRECTED = "status_corrected"


class GameEventItem(ApiModel):
    event_type: GameEventType
    confirmed: bool
    reason: str | None = None
    recorded_at: datetime


class GameEventsResponse(ApiModel):
    game_id: str
    events: list[GameEventItem]


class EventFeedItem(ApiModel):
    game_id: str
    event_type: GameEventType
    confirmed: bool
    reason: str | None = None
    recorded_at: datetime


class EventsFeedResponse(ApiModel):
    date: date
    events: list[EventFeedItem]
