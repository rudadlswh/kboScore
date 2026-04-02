from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from collector.models.season_classification import GameSeasonClassification


@dataclass(frozen=True, slots=True)
class NormalizedLiveGameState:
    source_name: str
    source_observed_at: datetime
    provider_game_ref: str
    status: str
    season_classification: GameSeasonClassification
    phase_text: str | None
    inning_number: int | None
    inning_half: str | None
    inning_label: str | None
    home_score: int
    away_score: int
    outs: int | None
    balls: int | None
    strikes: int | None
    bases_first: bool
    bases_second: bool
    bases_third: bool
    clock_text: str | None
    cancel_reason_text: str | None
    final_reason_text: str | None

    def __post_init__(self) -> None:
        if self.status not in {"scheduled", "live", "finished", "postponed", "cancelled"}:
            raise ValueError(f"Unsupported status: {self.status}")
        if self.season_classification not in set(GameSeasonClassification):
            raise ValueError(f"Unsupported season_classification: {self.season_classification}")
        if not self.provider_game_ref:
            raise ValueError("provider_game_ref must not be blank")
        if self.inning_half not in {None, "top", "bottom"}:
            raise ValueError("inning_half must be one of None, 'top', or 'bottom'")

    @property
    def inning_state(self) -> str | None:
        if self.inning_label:
            return self.inning_label
        return self.derive_inning_state()

    def derive_inning_state(self) -> str | None:
        if self.inning_number is None or self.inning_half is None:
            return self.phase_text or self.clock_text
        half_text = "초" if self.inning_half == "top" else "말"
        return f"{self.inning_number}회{half_text}"

    def is_live(self) -> bool:
        return self.status == "live"

    def is_final(self) -> bool:
        return self.status == "finished"

    def is_pregame(self) -> bool:
        return self.status == "scheduled"

    def is_postponed(self) -> bool:
        return self.status == "postponed"

    def change_detection_payload(self) -> dict:
        return {
            "status": self.status,
            "season_classification": self.season_classification.value,
            "phase_text": self.phase_text,
            "inning_number": self.inning_number,
            "inning_half": self.inning_half,
            "inning_label": self.inning_label,
            "home_score": self.home_score,
            "away_score": self.away_score,
            "outs": self.outs,
            "balls": self.balls,
            "strikes": self.strikes,
            "bases": {
                "first": self.bases_first,
                "second": self.bases_second,
                "third": self.bases_third,
            },
            "cancel_reason_text": self.cancel_reason_text,
            "final_reason_text": self.final_reason_text,
        }

    def to_payload_json(self) -> dict:
        return {
            "source_name": self.source_name,
            "source_observed_at": self.source_observed_at.isoformat(),
            "provider_game_ref": self.provider_game_ref,
            "status": self.status,
            "season_classification": self.season_classification.value,
            "phase_text": self.phase_text,
            "inning_number": self.inning_number,
            "inning_half": self.inning_half,
            "inning_label": self.inning_label,
            "home_score": self.home_score,
            "away_score": self.away_score,
            "outs": self.outs,
            "balls": self.balls,
            "strikes": self.strikes,
            "bases": {
                "first": self.bases_first,
                "second": self.bases_second,
                "third": self.bases_third,
            },
            "clock_text": self.clock_text,
            "cancel_reason_text": self.cancel_reason_text,
            "final_reason_text": self.final_reason_text,
        }

    @classmethod
    def change_detection_payload_from_payload_json(cls, payload_json: dict[str, Any] | None) -> dict[str, Any]:
        if not payload_json:
            return {}

        bases = payload_json.get("bases") or {}
        return {
            "status": payload_json.get("status"),
            "season_classification": payload_json.get("season_classification"),
            "phase_text": payload_json.get("phase_text"),
            "inning_number": payload_json.get("inning_number"),
            "inning_half": payload_json.get("inning_half"),
            "inning_label": payload_json.get("inning_label"),
            "home_score": payload_json.get("home_score"),
            "away_score": payload_json.get("away_score"),
            "outs": payload_json.get("outs"),
            "balls": payload_json.get("balls"),
            "strikes": payload_json.get("strikes"),
            "bases": {
                "first": bool(bases.get("first")),
                "second": bool(bases.get("second")),
                "third": bool(bases.get("third")),
            },
            "cancel_reason_text": payload_json.get("cancel_reason_text"),
            "final_reason_text": payload_json.get("final_reason_text"),
        }
