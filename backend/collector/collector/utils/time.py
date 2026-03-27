from __future__ import annotations

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo


KST = ZoneInfo("Asia/Seoul")


def now_kst() -> datetime:
    return datetime.now(tz=KST)


def today_kst() -> date:
    return now_kst().date()


def to_kst(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=KST)
    return value.astimezone(KST)


def recent_kst_window_start(value: datetime, hours: int = 6) -> datetime:
    return to_kst(value) - timedelta(hours=hours)


def is_weekend_game_date(game_date: date) -> bool:
    return game_date.weekday() >= 5


def weekday_1830_window_start(game_date: date) -> datetime:
    return datetime.combine(game_date, time(hour=14, minute=0), tzinfo=KST)


def scheduled_window_start(game_datetime: datetime) -> datetime:
    return to_kst(game_datetime) - timedelta(hours=4)


def weather_poll_bucket(value: datetime) -> datetime:
    value = to_kst(value)
    minute = 30 if value.minute >= 30 else 0
    return value.replace(minute=minute, second=0, microsecond=0)


def fifteen_minute_bucket(value: datetime) -> datetime:
    value = to_kst(value)
    minute = (value.minute // 15) * 15
    return value.replace(minute=minute, second=0, microsecond=0)


def weather_window_start(game_date: date, scheduled_at: datetime) -> datetime:
    scheduled_at = to_kst(scheduled_at)
    if is_weekend_game_date(game_date):
        return scheduled_window_start(scheduled_at)
    if scheduled_at.hour == 18 and scheduled_at.minute == 30:
        return weekday_1830_window_start(game_date)
    return scheduled_window_start(scheduled_at)


def is_weather_poll_due(
    *,
    now_at: datetime,
    game_date: date,
    scheduled_at: datetime | None,
    last_observed_at: datetime | None,
) -> tuple[bool, str]:
    now_at = to_kst(now_at)
    if scheduled_at is None:
        return False, "missing_scheduled_at"
    if game_date != now_at.date():
        return False, "not_same_day"

    start_at = weather_window_start(game_date, scheduled_at)
    if now_at < start_at:
        return False, "before_window"

    current_bucket = weather_poll_bucket(now_at)
    if last_observed_at is None:
        return True, "first_poll"

    if weather_poll_bucket(last_observed_at) < current_bucket:
        return True, "next_bucket"

    return False, "already_polled_bucket"
