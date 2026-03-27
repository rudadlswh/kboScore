from __future__ import annotations

from dataclasses import dataclass

import psycopg


@dataclass(slots=True)
class TeamMappingService:
    conn: psycopg.Connection

    OFFICIAL_TEAM_CODE_MAP = {
        "LG": "LG",
        "KT": "KT",
        "OB": "DOOSAN",
        "HT": "KIA",
        "LT": "LOTTE",
        "SS": "SAMSUNG",
        "HH": "HANWHA",
        "WO": "KIWOOM",
        "NC": "NC",
        "SK": "SSG",
        "SSG": "SSG",
        "KIA": "KIA",
        "DOOSAN": "DOOSAN",
        "LOTTE": "LOTTE",
        "SAMSUNG": "SAMSUNG",
        "HANWHA": "HANWHA",
        "KIWOOM": "KIWOOM",
        "두산": "DOOSAN",
        "롯데": "LOTTE",
        "삼성": "SAMSUNG",
        "한화": "HANWHA",
        "키움": "KIWOOM",
        "LG 트윈스": "LG",
        "LG트윈스": "LG",
        "KT 위즈": "KT",
        "KT위즈": "KT",
        "NC 다이노스": "NC",
        "NC다이노스": "NC",
        "SSG 랜더스": "SSG",
        "SSG랜더스": "SSG",
        "KIA 타이거즈": "KIA",
        "KIA타이거즈": "KIA",
        "두산 베어스": "DOOSAN",
        "두산베어스": "DOOSAN",
        "롯데 자이언츠": "LOTTE",
        "롯데자이언츠": "LOTTE",
        "삼성 라이온즈": "SAMSUNG",
        "삼성라이온즈": "SAMSUNG",
        "한화 이글스": "HANWHA",
        "한화이글스": "HANWHA",
        "키움 히어로즈": "KIWOOM",
        "키움히어로즈": "KIWOOM",
    }

    @classmethod
    def normalize_team_code(cls, official_code: str) -> str:
        normalized = official_code.strip()
        if not normalized:
            raise ValueError("Team code must not be blank")

        return cls.OFFICIAL_TEAM_CODE_MAP.get(
            normalized.upper(),
            cls.OFFICIAL_TEAM_CODE_MAP.get(normalized, normalized.upper()),
        )

    def resolve_team_id(self, official_code: str) -> str:
        canonical_code = self.normalize_team_code(official_code)
        with self.conn.cursor() as cur:
            cur.execute("SELECT id FROM teams WHERE code = %s", (canonical_code,))
            row = cur.fetchone()
        if row is None:
            raise ValueError(f"Unmapped team code: {official_code}")
        return str(row["id"])
