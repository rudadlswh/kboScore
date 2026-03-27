from __future__ import annotations

import json
from pathlib import Path
from typing import Any


FIXTURES_ROOT = Path(__file__).resolve().parents[1] / "fixtures"


def fixture_path(*relative_parts: str) -> Path:
    return FIXTURES_ROOT.joinpath(*relative_parts)


def load_text_fixture(*relative_parts: str) -> str:
    path = fixture_path(*relative_parts)
    return path.read_text(encoding="utf-8")


def load_json_fixture(*relative_parts: str) -> Any:
    path = fixture_path(*relative_parts)
    return json.loads(path.read_text(encoding="utf-8"))


def load_sql_fixture(*relative_parts: str) -> str:
    path = fixture_path(*relative_parts)
    return path.read_text(encoding="utf-8")
