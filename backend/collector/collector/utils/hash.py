from __future__ import annotations

import json
from hashlib import sha256
from typing import Any

from collector.models.live_models import NormalizedLiveGameState
from collector.models.weather_models import NormalizedWeatherSnapshot


def stable_json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def sha256_hexdigest(text: str) -> str:
    return sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes_hexdigest(data: bytes) -> str:
    return sha256(data).hexdigest()


def build_weather_content_hash(snapshot: NormalizedWeatherSnapshot) -> str:
    return sha256_hexdigest(stable_json_dumps(snapshot.content_hash_payload()))


def build_live_change_detection_hash(state: NormalizedLiveGameState) -> str:
    return sha256_hexdigest(stable_json_dumps(state.change_detection_payload()))
