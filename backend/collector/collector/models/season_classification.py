from __future__ import annotations

from enum import StrEnum


class GameSeasonClassification(StrEnum):
    UNKNOWN = "unknown"
    REGULAR_SEASON = "regular_season"
    EXHIBITION_PRESEASON = "exhibition_preseason"
    POSTSEASON = "postseason"


def classify_game_season_text(raw_text: str | None) -> GameSeasonClassification:
    if raw_text is None:
        return GameSeasonClassification.UNKNOWN

    normalized = raw_text.strip().lower()
    if not normalized:
        return GameSeasonClassification.UNKNOWN

    if "정규경기" in normalized or "regular season" in normalized:
        return GameSeasonClassification.REGULAR_SEASON

    if (
        "시범경기" in normalized
        or "preseason" in normalized
        or "exhibition" in normalized
    ):
        return GameSeasonClassification.EXHIBITION_PRESEASON

    if any(
        token in normalized
        for token in (
            "포스트시즌",
            "와일드카드",
            "준플레이오프",
            "플레이오프",
            "한국시리즈",
            "postseason",
            "wild card",
            "wildcard",
            "playoff",
            "korean series",
        )
    ):
        return GameSeasonClassification.POSTSEASON

    return GameSeasonClassification.UNKNOWN
