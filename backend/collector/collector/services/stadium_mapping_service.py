from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class StadiumMappingService:
    """
    MVP stadium code resolver backed by a fixed verified mapping captured during endpoint verification.
    """

    STADIUM_NAME_TO_CODE = {
        "잠실": "JS",
        "잠실야구장": "JS",
        "문학": "MH",
        "인천SSG랜더스필드": "MH",
        "대구": "DK",
        "대구삼성라이온즈파크": "DK",
        "대전": "DN",
        "대전 한화생명 볼파크": "DN",
        "창원": "CW",
        "창원NC파크": "CW",
        "고척": "GC",
        "고척스카이돔": "GC",
        "광주": "KC",
        "광주기아챔피언스필드": "KC",
        "사직": "SJ",
        "사직야구장": "SJ",
        "수원": "SW",
        "수원KT위즈파크": "SW",
        "울산": "UL",
        "울산문수야구장": "UL",
        "청주": "CJ",
        "청주야구장": "CJ",
        "포항": "PH",
        "포항야구장": "PH",
    }

    def resolve_stadium_code(self, stadium_name: str) -> str:
        normalized = " ".join(stadium_name.strip().split())
        if normalized.upper() in self.STADIUM_NAME_TO_CODE.values():
            return normalized.upper()
        code = self.STADIUM_NAME_TO_CODE.get(normalized)
        if code is None:
            raise ValueError(f"Unmapped stadium name: {stadium_name}")
        return code
