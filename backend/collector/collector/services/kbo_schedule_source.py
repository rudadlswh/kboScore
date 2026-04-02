from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import date, datetime, time
from html import unescape
from html.parser import HTMLParser
from typing import Protocol

from collector.models.season_classification import GameSeasonClassification, classify_game_season_text
from collector.models.schedule_models import NormalizedScheduleGame
from collector.services.team_mapping_service import TeamMappingService
from collector.utils.http import HTTPClient
from collector.utils.time import KST


@dataclass(frozen=True, slots=True)
class ScheduleSourceRequest:
    season_id: int
    month: int


class ScheduleSourceAdapter(Protocol):
    def fetch_month_schedule(self, request: ScheduleSourceRequest) -> list[NormalizedScheduleGame]:
        """Fetch normalized schedule rows from the primary assumed source."""

    def fetch_month_schedule_html(self, request: ScheduleSourceRequest) -> str:
        """Fetch raw HTML from the verified fallback public schedule page."""

    def parse_month_schedule_html(self, html: str, request: ScheduleSourceRequest) -> list[NormalizedScheduleGame]:
        """Parse fallback HTML into normalized schedule rows."""


class ScheduleSourceError(RuntimeError):
    """Raised when the schedule source cannot be fetched or normalized."""


class ScheduleParseError(ScheduleSourceError):
    """Raised when the payload shape or HTML row structure is not as expected."""


class _ScheduleTableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self._in_target_table = False
        self._table_depth = 0
        self._in_row = False
        self._in_cell = False
        self._current_row: list[str] = []
        self._current_cell: list[str] = []
        self.rows: list[list[str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        if tag == "table" and attrs_dict.get("id") == "tblScheduleList":
            self._in_target_table = True
            self._table_depth = 1
            return

        if not self._in_target_table:
            return

        if tag == "table":
            self._table_depth += 1
            return

        if tag == "tr":
            self._in_row = True
            self._current_row = []
            return

        if self._in_row and tag in {"td", "th"}:
            self._in_cell = True
            self._current_cell = []
            return

        if self._in_cell:
            self._current_cell.append(self._render_starttag(tag, attrs))

    def handle_endtag(self, tag: str) -> None:
        if not self._in_target_table:
            return

        if self._in_cell and tag not in {"td", "th"}:
            self._current_cell.append(f"</{tag}>")
            return

        if tag in {"td", "th"} and self._in_cell:
            self._current_row.append("".join(self._current_cell).strip())
            self._current_cell = []
            self._in_cell = False
            return

        if tag == "tr" and self._in_row:
            if self._current_row:
                self.rows.append(self._current_row)
            self._current_row = []
            self._in_row = False
            return

        if tag == "table":
            self._table_depth -= 1
            if self._table_depth <= 0:
                self._in_target_table = False

    def handle_data(self, data: str) -> None:
        if self._in_cell:
            self._current_cell.append(data)

    def handle_entityref(self, name: str) -> None:
        if self._in_cell:
            self._current_cell.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        if self._in_cell:
            self._current_cell.append(f"&#{name};")

    @staticmethod
    def _render_starttag(tag: str, attrs: list[tuple[str, str | None]]) -> str:
        if not attrs:
            return f"<{tag}>"
        rendered_attrs = " ".join(
            f'{key}="{value}"' if value is not None else key
            for key, value in attrs
        )
        return f"<{tag} {rendered_attrs}>"


class KBOScheduleSource:
    """
    Primary source: assumed KBO AJAX schedule endpoint.
    Fallback source: verified public Schedule.aspx HTML page.

    The primary path is operationally preferred for MVP because the public HTML page
    currently relies on client-side hydration. The HTML fallback is still implemented
    as a best-effort parser and raises a clear error when schedule rows are absent.
    """

    PRIMARY_URL = "https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList"
    FALLBACK_URL = "https://www.koreabaseball.com/Schedule/Schedule.aspx"
    def __init__(self, http_client: HTTPClient | None = None) -> None:
        self.http_client = http_client or HTTPClient()

    def fetch_month_schedule(self, request: ScheduleSourceRequest) -> list[NormalizedScheduleGame]:
        series_id_list = self.series_id_list_for_request(request)
        try:
            response = self.http_client.post(
                self.PRIMARY_URL,
                form_data={
                    "leId": "1",
                    "srIdList": series_id_list,
                    "seasonId": str(request.season_id),
                    "gameMonth": f"{request.month:02d}",
                    "teamId": "",
                },
                headers={"X-Requested-With": "XMLHttpRequest"},
            )
            payload = json.loads(response.text)
            return self._parse_primary_payload(payload, request)
        except Exception as primary_error:
            html = self.fetch_month_schedule_html(request)
            try:
                return self.parse_month_schedule_html(html, request)
            except Exception as fallback_error:
                raise ScheduleSourceError(
                    f"Primary and fallback schedule fetch failed for {request.season_id}-{request.month:02d}: "
                    f"primary={primary_error!r}, fallback={fallback_error!r}"
                ) from fallback_error

    def fetch_month_schedule_html(self, request: ScheduleSourceRequest) -> str:
        series_id_list = self.series_id_list_for_request(request)
        response = self.http_client.get(
            f"{self.FALLBACK_URL}?seriesId={series_id_list}&date={request.season_id}{request.month:02d}01"
        )
        return response.text

    @staticmethod
    def series_id_list_for_request(request: ScheduleSourceRequest) -> str:
        # Verified source behavior: March mixes preseason and opening regular-season rows.
        return "0,9" if request.month == 3 else "0"

    def parse_month_schedule_html(self, html: str, request: ScheduleSourceRequest) -> list[NormalizedScheduleGame]:
        parser = _ScheduleTableParser()
        parser.feed(html)
        parser.close()

        if not parser.rows:
            raise ScheduleParseError(
                "Schedule fallback HTML did not contain any data rows under #tblScheduleList. "
                "Current public KBO schedule page appears to be client-side hydrated."
            )

        games: list[NormalizedScheduleGame] = []
        current_date: date | None = None
        for row_index, cells in enumerate(parser.rows):
            try:
                current_date, game = self._normalize_cells(
                    cells,
                    request,
                    current_date=current_date,
                    source_name="schedule_html_fallback",
                )
            except ScheduleParseError as error:
                if any("날짜" in self._strip_html(cell) for cell in cells):
                    continue
                raise ScheduleParseError(f"Fallback HTML row {row_index} parse failed: {error}") from error
            if game is not None:
                games.append(game)

        if not games:
            raise ScheduleParseError("Fallback HTML parser found the table but could not normalize any schedule rows")

        return games

    def derive_provider_game_id(
        self,
        *,
        game_date: date,
        away_team_code: str,
        home_team_code: str,
        stadium: str,
        scheduled_at: datetime | None,
    ) -> str:
        time_part = scheduled_at.astimezone(KST).strftime("%H%M") if scheduled_at else "TBD"
        stadium_part = re.sub(r"\s+", "", stadium).upper() if stadium else "UNKNOWN"
        return f"kbo:{game_date.strftime('%Y%m%d')}:{away_team_code}:{home_team_code}:{stadium_part}:{time_part}:0"

    def _parse_primary_payload(
        self,
        payload: dict,
        request: ScheduleSourceRequest,
    ) -> list[NormalizedScheduleGame]:
        rows = payload.get("rows")
        if not isinstance(rows, list):
            raise ScheduleParseError("Primary schedule payload did not contain a rows list")

        games: list[NormalizedScheduleGame] = []
        current_date: date | None = None
        for row_index, row_entry in enumerate(rows):
            cells = row_entry.get("row")
            if not isinstance(cells, list):
                raise ScheduleParseError(f"Primary schedule row {row_index} is missing row cells")

            current_date, game = self._normalize_cells(
                [self._extract_primary_cell_text(cell) for cell in cells],
                request,
                current_date=current_date,
                source_name="schedule_ajax",
            )
            if game is not None:
                games.append(game)

        return games

    def _normalize_cells(
        self,
        cells: list[str],
        request: ScheduleSourceRequest,
        *,
        current_date: date | None,
        source_name: str,
    ) -> tuple[date | None, NormalizedScheduleGame | None]:
        if not cells:
            return current_date, None

        has_day_cell = self._looks_like_day_cell(cells[0])
        if has_day_cell:
            current_date = self._parse_day_cell(cells[0], request.season_id)
            offset = 1
        else:
            offset = 0

        if current_date is None:
            raise ScheduleParseError("Encountered a schedule row before any date header row")

        expected_cells = offset + 8
        if len(cells) < expected_cells:
            raise ScheduleParseError(f"Schedule row is too short: expected at least {expected_cells} cells, got {len(cells)}")

        time_html = cells[offset + 0]
        play_html = cells[offset + 1]
        relay_html = cells[offset + 2]
        stadium_html = cells[offset + 6]
        note_html = cells[offset + 7]

        if any(header in self._strip_html(play_html) for header in {"경기", "게임센터"}):
            return current_date, None

        scheduled_at = self._parse_scheduled_at(time_html, current_date)
        away_team_code, home_team_code = self._parse_matchup(play_html)
        stadium = self._strip_html(stadium_html)
        if not stadium:
            raise ScheduleParseError("Schedule row is missing stadium text")

        relay_text = self._strip_html(relay_html)
        note_text = self._strip_html(note_html)
        official_game_id = self._extract_game_id(relay_html)
        status = self._normalize_status(play_html=play_html, relay_text=relay_text, note_text=note_text)
        season_classification = self._derive_season_classification(
            request=request,
            play_html=play_html,
            relay_text=relay_text,
            note_text=note_text,
        )

        if official_game_id:
            provider_game_id = official_game_id
            official_provider_game_id = official_game_id
            provider_game_id_kind = "official"
        else:
            provider_game_id = self.derive_provider_game_id(
                game_date=current_date,
                away_team_code=away_team_code,
                home_team_code=home_team_code,
                stadium=stadium,
                scheduled_at=scheduled_at,
            )
            official_provider_game_id = None
            provider_game_id_kind = "derived"

        return current_date, NormalizedScheduleGame(
            provider="kbo",
            provider_game_id=provider_game_id,
            official_provider_game_id=official_provider_game_id,
            provider_game_id_kind=provider_game_id_kind,
            game_date=current_date,
            scheduled_at=scheduled_at,
            stadium=stadium,
            stadium_code=None,
            home_team_code=home_team_code,
            away_team_code=away_team_code,
            status=status,
            season_classification=season_classification,
            source_name=source_name,
        )

    @staticmethod
    def _extract_primary_cell_text(cell: dict) -> str:
        text = cell.get("Text")
        if not isinstance(text, str):
            raise ScheduleParseError(f"Unexpected primary cell payload: {cell!r}")
        return text

    @staticmethod
    def _looks_like_day_cell(text: str) -> bool:
        return bool(re.search(r"\d{2}\.\d{2}\([^)]+\)", KBOScheduleSource._strip_html(text)))

    @staticmethod
    def _parse_day_cell(text: str, season_id: int) -> date:
        match = re.search(r"(?P<month>\d{2})\.(?P<day>\d{2})\([^)]+\)", KBOScheduleSource._strip_html(text))
        if not match:
            raise ScheduleParseError(f"Could not parse schedule day cell: {text!r}")
        return date(season_id, int(match.group("month")), int(match.group("day")))

    @staticmethod
    def _parse_scheduled_at(time_html: str, game_date: date) -> datetime | None:
        match = re.search(r"(\d{1,2}):(\d{2})", KBOScheduleSource._strip_html(time_html))
        if not match:
            return None
        return datetime.combine(
            game_date,
            time(hour=int(match.group(1)), minute=int(match.group(2))),
            tzinfo=KST,
        )

    @staticmethod
    def _parse_matchup(play_html: str) -> tuple[str, str]:
        span_texts = [
            KBOScheduleSource._strip_html(match)
            for match in re.findall(r"<span[^>]*>(.*?)</span>", play_html, flags=re.IGNORECASE | re.DOTALL)
        ]
        tokens = [token.strip() for token in span_texts if token and token.strip()]
        if not tokens:
            raise ScheduleParseError(f"Could not parse matchup tokens from play cell: {play_html!r}")

        vs_index = None
        for index, token in enumerate(tokens):
            if token.lower() == "vs":
                vs_index = index
                break
        if vs_index is None:
            raise ScheduleParseError(f"Could not locate vs token in play cell: {play_html!r}")

        away_raw = KBOScheduleSource._find_team_token(tokens[:vs_index], reverse=True)
        home_raw = KBOScheduleSource._find_team_token(tokens[vs_index + 1 :], reverse=False)
        if away_raw is None or home_raw is None:
            raise ScheduleParseError(f"Could not resolve away/home team tokens from play cell: {play_html!r}")

        return (
            TeamMappingService.normalize_team_code(away_raw),
            TeamMappingService.normalize_team_code(home_raw),
        )

    @staticmethod
    def _find_team_token(tokens: list[str], *, reverse: bool) -> str | None:
        iterable = reversed(tokens) if reverse else tokens
        for token in iterable:
            if token.lower() == "vs":
                continue
            if re.fullmatch(r"\d+", token):
                continue
            return token
        return None

    @staticmethod
    def _extract_game_id(relay_html: str) -> str | None:
        match = re.search(r"[?&]gameId=([A-Za-z0-9]+)", relay_html)
        return match.group(1) if match else None

    @staticmethod
    def _normalize_status(*, play_html: str, relay_text: str, note_text: str) -> str:
        if any(flag in note_text for flag in ("우천취소", "연기", "노게임", "서스펜디드")):
            return "postponed"
        if "취소" in note_text:
            return "cancelled"
        if "리뷰" in relay_text or "HIGHLIGHT" in relay_text.upper():
            return "finished"
        if re.search(r'class\s*=\s*"win"|class\s*=\s*"lose"', play_html):
            return "finished"
        if "프리뷰" in relay_text or "START_PIT" in relay_text.upper():
            return "scheduled"
        return "scheduled"

    @staticmethod
    def _derive_season_classification(
        *,
        request: ScheduleSourceRequest,
        play_html: str,
        relay_text: str,
        note_text: str,
    ) -> GameSeasonClassification:
        for candidate in (
            KBOScheduleSource._strip_html(play_html),
            relay_text,
            note_text,
        ):
            classification = classify_game_season_text(candidate)
            if classification != GameSeasonClassification.UNKNOWN:
                return classification

        if request.month != 3:
            return GameSeasonClassification.REGULAR_SEASON

        return GameSeasonClassification.UNKNOWN

    @staticmethod
    def _strip_html(value: str) -> str:
        normalized = re.sub(r"<br\s*/?>", " ", value, flags=re.IGNORECASE)
        normalized = re.sub(r"<[^>]+>", "", normalized)
        return re.sub(r"\s+", " ", unescape(normalized)).strip()
