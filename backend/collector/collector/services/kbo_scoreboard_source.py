from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from datetime import date, datetime
from html import unescape

from collector.models.live_models import NormalizedLiveGameState
from collector.models.season_classification import classify_game_season_text
from collector.utils.http import HTTPClient
from collector.utils.time import KST

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class LiveScoreSourceRequest:
    game_date: date


class LiveScoreSourceError(RuntimeError):
    def __init__(self, message: str, *, source_name: str, response_text: str | None = None) -> None:
        super().__init__(message)
        self.source_name = source_name
        self.response_text = response_text


class LiveScoreParseError(LiveScoreSourceError):
    """Raised when the scoreboard source cannot be normalized."""


class KBOScoreboardSource:
    """
    Primary source: verified public ScoreBoard.aspx HTML page.
    Supplement / fallback source: assumed KBO AJAX GetKboGameList endpoint.

    The HTML page is attempted first because it is the verified public scoreboard surface.
    When the page is empty or no stable selectors are matched, the collector falls back
    to the same-day AJAX payload for conservative normalized state.
    """

    SCOREBOARD_URL = "https://www.koreabaseball.com/Schedule/ScoreBoard.aspx"
    LIVE_LIST_URL = "https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList"

    def __init__(self, http_client: HTTPClient | None = None) -> None:
        self.http_client = http_client or HTTPClient()

    def fetch_scoreboard_html(self, request: LiveScoreSourceRequest) -> str:
        response = self.http_client.get(self.SCOREBOARD_URL)
        return response.text

    def parse_scoreboard_html(self, html: str, request: LiveScoreSourceRequest) -> list[NormalizedLiveGameState]:
        # The current public page is server-rendered only for the selected current date and often
        # contains no game rows. Keep selectors isolated here so they are easy to adjust later.
        if "데이터가 존재하지 않습니다" in html:
            return []

        # MVP parser is intentionally conservative. If no stable game blocks are found, use fallback.
        game_blocks = self._extract_game_blocks(html)
        if not game_blocks:
            return []

        observed_at = datetime.now(tz=KST)
        states: list[NormalizedLiveGameState] = []
        for block in game_blocks:
            state = self._parse_html_game_block(block, observed_at)
            if state is not None:
                states.append(state)
        return states

    def fetch_live_game_list(self, request: LiveScoreSourceRequest) -> list[NormalizedLiveGameState]:
        response = self.http_client.post(
            self.LIVE_LIST_URL,
            form_data={
                "leId": "1",
                "srId": "0,1,3,4,5,7,8,9",
                "date": request.game_date.strftime("%Y%m%d"),
            },
            headers={"X-Requested-With": "XMLHttpRequest"},
        )
        try:
            payload = json.loads(response.text)
        except json.JSONDecodeError as error:
            raise LiveScoreParseError(
                f"Fallback live list response is not valid JSON: {error}",
                source_name="scoreboard_ajax_fallback",
                response_text=response.text,
            ) from error

        games = payload.get("game")
        if not isinstance(games, list):
            raise LiveScoreParseError(
                "Fallback live list payload is missing game list",
                source_name="scoreboard_ajax_fallback",
                response_text=response.text,
            )

        observed_at = datetime.now(tz=KST)
        states: list[NormalizedLiveGameState] = []
        for item in games:
            if not isinstance(item, dict):
                continue
            states.append(self._normalize_ajax_game(item, observed_at))
        return states

    def fetch_live_game_states(self, request: LiveScoreSourceRequest) -> list[NormalizedLiveGameState]:
        html = self.fetch_scoreboard_html(request)
        try:
            html_states = self.parse_scoreboard_html(html, request)
        except Exception as html_error:
            try:
                return self.fetch_live_game_list(request)
            except Exception as fallback_error:
                raise LiveScoreSourceError(
                    f"Primary and fallback live fetch failed for {request.game_date.isoformat()}: "
                    f"primary={html_error!r}, fallback={fallback_error!r}",
                    source_name="scoreboard_ajax_fallback",
                    response_text=html,
                ) from fallback_error

        if html_states:
            return html_states

        try:
            return self.fetch_live_game_list(request)
        except Exception as fallback_error:
            if "데이터가 존재하지 않습니다" in html:
                return []
            raise LiveScoreSourceError(
                f"HTML scoreboard returned no normalized rows and fallback failed: {fallback_error!r}",
                source_name="scoreboard_ajax_fallback",
                response_text=html,
            ) from fallback_error

    @staticmethod
    def _extract_game_blocks(html: str) -> list[str]:
        # Selector risk: current public page is not reliably server-rendered. Keep patterns local.
        patterns = [
            r'(<div[^>]+class="[^"]*game-cont[^"]*"[\s\S]*?</div>\s*</div>)',
            r'(<li[^>]+class="[^"]*game-list-item[^"]*"[\s\S]*?</li>)',
        ]
        for pattern in patterns:
            blocks = re.findall(pattern, html, flags=re.IGNORECASE)
            if blocks:
                return blocks
        return []

    def _parse_html_game_block(self, block: str, observed_at: datetime) -> NormalizedLiveGameState | None:
        game_id_match = re.search(r"[?&]gameId=([A-Za-z0-9]+)", block)
        if not game_id_match:
            return None

        provider_game_ref = game_id_match.group(1)
        score_numbers = [int(match) for match in re.findall(r"<em[^>]*>(\d+)</em>", block)]
        away_score = score_numbers[0] if len(score_numbers) >= 1 else 0
        home_score = score_numbers[1] if len(score_numbers) >= 2 else 0

        inning_label = self._extract_clean_text(block, r'(\d+회[초말])')
        inning_number, inning_half = self._parse_inning_label(inning_label)
        phase_text = self._extract_clean_text(block, r'<span[^>]+class="[^"]*state[^"]*"[^>]*>(.*?)</span>')
        clock_text = self._extract_clean_text(block, r'<span[^>]+class="[^"]*time[^"]*"[^>]*>(.*?)</span>')

        status = "live" if inning_label else "scheduled"
        return NormalizedLiveGameState(
            source_name="scoreboard_html",
            source_observed_at=observed_at,
            provider_game_ref=provider_game_ref,
            status=status,
            season_classification=classify_game_season_text(phase_text),
            phase_text=phase_text,
            inning_number=inning_number,
            inning_half=inning_half,
            inning_label=inning_label,
            home_score=home_score,
            away_score=away_score,
            outs=None,
            balls=None,
            strikes=None,
            bases_first=False,
            bases_second=False,
            bases_third=False,
            clock_text=clock_text,
            cancel_reason_text=None,
            final_reason_text=None,
        )

    def _normalize_ajax_game(self, item: dict, observed_at: datetime) -> NormalizedLiveGameState:
        cancel_reason = self._normalize_text(item.get("CANCEL_SC_NM"))
        cancel_code = self._normalize_text(item.get("CANCEL_SC_ID"))
        game_state = self._normalize_text(item.get("GAME_STATE_SC"))
        game_result = int(item.get("GAME_RESULT_CK") or 0)
        raw_game_phase = self._normalize_text(item.get("GAME_SC_NM"))
        phase_text = raw_game_phase or cancel_reason
        season_classification = classify_game_season_text(raw_game_phase)
        inning_number = self._parse_int(item.get("GAME_INN_NO"))
        inning_half = self._normalize_half(item.get("GAME_TB_SC"))
        if inning_number is None or inning_half is None:
            inferred_inning_number, inferred_inning_half = self._parse_inning_from_phase_text(phase_text)
            inning_number = inning_number if inning_number is not None else inferred_inning_number
            inning_half = inning_half if inning_half is not None else inferred_inning_half
        inning_label = self._build_inning_label(inning_number, inning_half)
        home_score = self._parse_int(item.get("B_SCORE_CN")) or 0
        away_score = self._parse_int(item.get("T_SCORE_CN")) or 0

        status = self._map_status(
            cancel_code=cancel_code,
            cancel_reason=cancel_reason,
            game_state=game_state,
            game_result=game_result,
            phase_text=phase_text,
            inning_number=inning_number,
            home_score=home_score,
            away_score=away_score,
        )
        provider_game_ref = self._require_text(item.get("G_ID"), "G_ID")

        logger.info(
            "live_status_mapped",
            extra={
                "source_name": "scoreboard_ajax_fallback",
                "provider_game_ref": provider_game_ref,
                "raw_game_state": game_state,
                "raw_phase_text": phase_text,
                "raw_cancel_code": cancel_code,
                "raw_cancel_reason": cancel_reason,
                "mapped_status": status,
                "inning_label": inning_label,
                "home_score": home_score,
                "away_score": away_score,
            },
        )

        final_reason_text = cancel_reason if status == "finished" and cancel_reason and cancel_reason != "정상경기" else None
        cancel_reason_text = cancel_reason if status in {"postponed", "cancelled"} else None

        return NormalizedLiveGameState(
            source_name="scoreboard_ajax_fallback",
            source_observed_at=observed_at,
            provider_game_ref=provider_game_ref,
            status=status,
            season_classification=season_classification,
            phase_text=phase_text,
            inning_number=inning_number,
            inning_half=inning_half,
            inning_label=inning_label,
            home_score=home_score,
            away_score=away_score,
            outs=self._parse_int(item.get("OUT_CN")),
            balls=self._parse_int(item.get("BALL_CN")),
            strikes=self._parse_int(item.get("STRIKE_CN")),
            bases_first=(self._parse_int(item.get("B1_BAT_ORDER_NO")) or 0) > 0,
            bases_second=(self._parse_int(item.get("B2_BAT_ORDER_NO")) or 0) > 0,
            bases_third=(self._parse_int(item.get("B3_BAT_ORDER_NO")) or 0) > 0,
            clock_text=self._normalize_text(item.get("G_TM")),
            cancel_reason_text=cancel_reason_text,
            final_reason_text=final_reason_text,
        )

    @staticmethod
    def _map_status(
        *,
        cancel_code: str | None,
        cancel_reason: str | None,
        game_state: str | None,
        game_result: int,
        phase_text: str | None,
        inning_number: int | None,
        home_score: int,
        away_score: int,
    ) -> str:
        if cancel_code and cancel_code not in {"0", "9"}:
            if cancel_reason and any(flag in cancel_reason for flag in ("우천취소", "연기", "노게임", "서스펜디드")):
                return "postponed"
            if cancel_reason and "취소" in cancel_reason:
                return "cancelled"
            return "postponed"

        if game_result == 1 or game_state == "3":
            return "finished"

        if game_state in {"1", "2"}:
            return "live"

        if phase_text and KBOScoreboardSource._is_live_phase_text(phase_text):
            return "live"

        if inning_number is not None or home_score > 0 or away_score > 0:
            return "live"

        return "scheduled"

    @staticmethod
    def _parse_inning_label(inning_label: str | None) -> tuple[int | None, str | None]:
        if not inning_label:
            return None, None
        match = re.fullmatch(r"(\d+)회(초|말)", inning_label)
        if not match:
            return None, None
        return int(match.group(1)), "top" if match.group(2) == "초" else "bottom"

    @staticmethod
    def _build_inning_label(inning_number: int | None, inning_half: str | None) -> str | None:
        if inning_number is None or inning_half is None:
            return None
        return f"{inning_number}회{'초' if inning_half == 'top' else '말'}"

    @staticmethod
    def _parse_inning_from_phase_text(phase_text: str | None) -> tuple[int | None, str | None]:
        if not phase_text:
            return None, None
        match = re.search(r"(\d+)\s*회\s*(초|말)", phase_text)
        if not match:
            return None, None
        inning_number = int(match.group(1))
        inning_half = "top" if match.group(2) == "초" else "bottom"
        return inning_number, inning_half

    @staticmethod
    def _is_live_phase_text(phase_text: str) -> bool:
        compact_text = re.sub(r"\s+", "", phase_text)
        if re.search(r"\d+회(초|말)", compact_text):
            return True
        return any(keyword in compact_text for keyword in ("경기중", "진행중", "연장", "클리닝타임"))

    @staticmethod
    def _normalize_half(value: object) -> str | None:
        text = KBOScoreboardSource._normalize_text(value)
        if text == "T":
            return "top"
        if text == "B":
            return "bottom"
        return None

    @staticmethod
    def _parse_int(value: object) -> int | None:
        if value is None:
            return None
        text = str(value).strip()
        if not text:
            return None
        try:
            return int(float(text))
        except ValueError:
            return None

    @staticmethod
    def _normalize_text(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _require_text(value: object, field_name: str) -> str:
        text = KBOScoreboardSource._normalize_text(value)
        if text is None:
            raise LiveScoreParseError(
                f"Missing required live field: {field_name}",
                source_name="scoreboard_ajax_fallback",
                response_text=json.dumps({field_name: value}, ensure_ascii=False),
            )
        return text

    @staticmethod
    def _extract_clean_text(block: str, pattern: str) -> str | None:
        match = re.search(pattern, block, flags=re.IGNORECASE | re.DOTALL)
        if not match:
            return None
        text = re.sub(r"<[^>]+>", "", match.group(1))
        return re.sub(r"\s+", " ", unescape(text)).strip() or None
