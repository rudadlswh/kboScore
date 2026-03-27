from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import date, datetime
from html import unescape

from collector.models.weather_models import NormalizedWeatherSnapshot
from collector.utils.http import HTTPClient
from collector.utils.time import KST


@dataclass(frozen=True, slots=True)
class WeatherSourceRequest:
    stadium_code: str
    home_code: str | None
    away_code: str | None
    league_id: int = 1


@dataclass(frozen=True, slots=True)
class TodayGameStatus:
    stadium_code: str
    stadium_name: str
    home_code: str | None
    away_code: str | None
    game_sc: str | None
    game_time: str | None


class WeatherSourceError(RuntimeError):
    def __init__(self, message: str, *, source_name: str, response_text: str | None = None) -> None:
        super().__init__(message)
        self.source_name = source_name
        self.response_text = response_text


class WeatherParseError(WeatherSourceError):
    """Raised when weather payload parsing fails."""


class KBOWeatherSource:
    """
    Primary source: assumed KBO AJAX weather endpoints.
    Fallback source: verified public Weather.aspx page.

    The public HTML page is currently client-side hydrated, so the fallback parser is
    intentionally conservative and raises when the page appears to contain placeholder content.
    """

    WEATHER_URL = "https://www.koreabaseball.com/ws/Schedule.asmx/GetStadiumWeather"
    FORECAST_URL = "https://www.koreabaseball.com/ws/Schedule.asmx/GetStadiumForecast"
    TODAY_GAMES_URL = "https://www.koreabaseball.com/ws/Schedule.asmx/GetTodayGames"
    WEATHER_PAGE_URL = "https://www.koreabaseball.com/Schedule/Weather.aspx"

    STADIUM_CODE_TO_NAME = {
        "JS": "잠실",
        "MH": "문학",
        "DK": "대구",
        "DN": "대전",
        "CW": "창원",
        "GC": "고척",
        "KC": "광주",
        "SJ": "사직",
        "SW": "수원",
        "UL": "울산",
        "CJ": "청주",
        "PH": "포항",
    }

    def __init__(self, http_client: HTTPClient | None = None) -> None:
        self.http_client = http_client or HTTPClient()

    def fetch_stadium_weather(self, request: WeatherSourceRequest) -> NormalizedWeatherSnapshot:
        try:
            response = self.http_client.post(
                self.WEATHER_URL,
                form_data={
                    "stadium": request.stadium_code,
                    "home": request.home_code or "",
                    "away": request.away_code or "",
                    "leId": str(request.league_id),
                },
                headers={"X-Requested-With": "XMLHttpRequest"},
            )
            payload = json.loads(response.text)
            try:
                forecast_payload = self.fetch_stadium_forecast(
                    request.stadium_code,
                    datetime.now(tz=KST).strftime("%Y%m%d"),
                    0,
                )
            except Exception:
                forecast_payload = {}
            return self._normalize_ajax_payload(request, payload, forecast_payload)
        except Exception as primary_error:
            html = self.fetch_weather_page(request.stadium_code, request.league_id)
            try:
                return self.parse_weather_page(html, request.stadium_code)
            except Exception as fallback_error:
                raise WeatherSourceError(
                    f"Primary and fallback weather fetch failed for {request.stadium_code}: "
                    f"primary={primary_error!r}, fallback={fallback_error!r}",
                    source_name="weather_html_fallback",
                    response_text=html,
                ) from fallback_error

    def fetch_stadium_forecast(self, stadium_code: str, game_date_text: str, day_offset: int) -> dict:
        response = self.http_client.post(
            self.FORECAST_URL,
            form_data={
                "gameDate": game_date_text,
                "stadium": stadium_code,
                "day": str(day_offset),
            },
            headers={"X-Requested-With": "XMLHttpRequest"},
        )
        payload = json.loads(response.text)
        if not isinstance(payload, dict):
            raise WeatherParseError(
                f"Forecast payload is not an object for stadium {stadium_code}",
                source_name="weather_forecast_ajax",
                response_text=response.text,
            )
        return payload

    def fetch_weather_page(self, stadium_code: str, league_id: int = 1) -> str:
        response = self.http_client.get(f"{self.WEATHER_PAGE_URL}?stadium={stadium_code}&leId={league_id}")
        return response.text

    def parse_weather_page(self, html: str, stadium_code: str) -> NormalizedWeatherSnapshot:
        stadium_name = self._extract_html_value(
            html,
            r'<p class="title">.*?<span>(.*?) 현재 날씨</span>',
            source_name="weather_html_fallback",
            response_text=html,
        )
        expected_name = self.STADIUM_CODE_TO_NAME.get(stadium_code)
        if expected_name and expected_name not in stadium_name:
            raise WeatherParseError(
                f"Fallback HTML appears unhydrated for stadium {stadium_code}: parsed title={stadium_name!r}",
                source_name="weather_html_fallback",
                response_text=html,
            )

        icon_code = self._extract_icon_code(html)
        icon_name = self._extract_html_value(
            html,
            r'<div class="weather">\s*<img[^>]+>\s*<p>(.*?)</p>',
            source_name="weather_html_fallback",
            response_text=html,
        )
        temp_text = self._extract_html_value(
            html,
            r'<p class="celsius">([^<]+)</p>',
            source_name="weather_html_fallback",
            response_text=html,
        )
        etc_values = re.findall(r"<ul class=\"etc\">.*?<dd>(.*?)</dd>", html, flags=re.IGNORECASE | re.DOTALL)
        if len(etc_values) < 3:
            raise WeatherParseError(
                "Fallback HTML did not contain enough current weather values under .etc",
                source_name="weather_html_fallback",
                response_text=html,
            )

        memo_text = self._extract_html_value(
            html,
            r'<div class="memo">\s*<p>(.*?)</p>',
            source_name="weather_html_fallback",
            response_text=html,
        )
        status_match = re.search(r'<p class="txt">(.*?)</p>', html, flags=re.IGNORECASE | re.DOTALL)
        status_text = self._clean_html(status_match.group(1)) if status_match else None

        forecast_issued_at = self._parse_cast_datetime(memo_text.replace(" 기준", ""))
        return NormalizedWeatherSnapshot(
            source_name="weather_html_fallback",
            source_observed_at=forecast_issued_at or datetime.now(tz=KST),
            stadium_code=stadium_code,
            stadium_name=stadium_name,
            forecast_issued_at=forecast_issued_at,
            home_team_code=None,
            away_team_code=None,
            scheduled_game_time=None,
            current_icon_code=icon_code,
            current_icon_name=icon_name,
            current_temp_c=self._parse_float(temp_text.replace("℃", "")),
            current_rain_mm=self._parse_float(etc_values[0].replace("mm", "")),
            current_rain_raw=self._clean_html(etc_values[0]).replace("mm", "").strip(),
            current_humidity_pct=self._parse_int(etc_values[1].replace("%", "")),
            current_wind_speed_ms=self._parse_float(etc_values[2].replace("m/s", "")),
            status_text=status_text,
            raw_payload={"html_fallback": {"memo": memo_text}},
        )

    def fetch_today_game_statuses(self, game_date: date, league_id: int = 1) -> dict[tuple[str, str | None, str | None], TodayGameStatus]:
        response = self.http_client.post(
            self.TODAY_GAMES_URL,
            form_data={
                "gameDate": game_date.strftime("%Y%m%d"),
                "leId": str(league_id),
                "srId": "0,1,2,3,4,5,6,7,8,9",
                "headerCk": "1",
            },
            headers={"X-Requested-With": "XMLHttpRequest"},
        )
        payload = json.loads(response.text)
        if not isinstance(payload, dict):
            raise WeatherParseError(
                "Today games payload is not an object",
                source_name="today_games_ajax",
                response_text=response.text,
            )

        game_list = payload.get("gameList") or []
        if not isinstance(game_list, list):
            raise WeatherParseError(
                "Today games payload missing gameList",
                source_name="today_games_ajax",
                response_text=response.text,
            )

        status_map: dict[tuple[str, str | None, str | None], TodayGameStatus] = {}
        for game in game_list:
            if not isinstance(game, dict):
                continue
            item = TodayGameStatus(
                stadium_code=str(game.get("stadium", "")).strip(),
                stadium_name=str(game.get("stadiumFullName", "")).strip(),
                home_code=self._normalize_code(game.get("homeCode")),
                away_code=self._normalize_code(game.get("awayCode")),
                game_sc=self._normalize_code(game.get("gameSc")),
                game_time=self._normalize_code(game.get("gameTime")),
            )
            status_map[(item.stadium_code, item.home_code, item.away_code)] = item
        return status_map

    def _normalize_ajax_payload(
        self,
        request: WeatherSourceRequest,
        payload: dict,
        forecast_payload: dict,
    ) -> NormalizedWeatherSnapshot:
        if not isinstance(payload, dict) or not payload.get("stadiumCode"):
            raise WeatherParseError(
                f"Primary weather payload missing stadiumCode for {request.stadium_code}",
                source_name="weather_ajax",
                response_text=json.dumps(payload, ensure_ascii=False),
            )

        forecast_issued_at = self._parse_forecast_reg_dt(forecast_payload.get("regDt"))
        if forecast_issued_at is None:
            forecast_issued_at = self._parse_cast_datetime(payload.get("castDate"))

        return NormalizedWeatherSnapshot(
            source_name="weather_ajax",
            source_observed_at=forecast_issued_at or datetime.now(tz=KST),
            stadium_code=str(payload["stadiumCode"]),
            stadium_name=str(payload.get("stadium", "")),
            forecast_issued_at=forecast_issued_at,
            home_team_code=self._normalize_code(payload.get("homeCode")),
            away_team_code=self._normalize_code(payload.get("awayCode")),
            scheduled_game_time=self._normalize_code(payload.get("todayTime")),
            current_icon_code=self._normalize_code(payload.get("icon")),
            current_icon_name=self._normalize_code(payload.get("iconName")),
            current_temp_c=self._parse_float(payload.get("temp")),
            current_rain_mm=self._parse_float(payload.get("rain")),
            current_rain_raw=self._normalize_code(payload.get("rain")),
            current_humidity_pct=self._parse_int(payload.get("humi")),
            current_wind_speed_ms=self._parse_float(payload.get("wind")),
            status_text=None,
            raw_payload={
                "weather": payload,
                "forecast": forecast_payload,
            },
        )

    @staticmethod
    def _parse_forecast_reg_dt(value: object) -> datetime | None:
        if not value:
            return None
        text = str(value).strip()
        match = re.fullmatch(r"(\d{4})\.(\d{2})\.(\d{2}) (\d{2})", text)
        if not match:
            return None
        return datetime(
            year=int(match.group(1)),
            month=int(match.group(2)),
            day=int(match.group(3)),
            hour=int(match.group(4)),
            minute=0,
            tzinfo=KST,
        )

    @staticmethod
    def _parse_cast_datetime(value: object) -> datetime | None:
        if not value:
            return None
        text = str(value).strip()
        match = re.fullmatch(r"(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})", text)
        if not match:
            return None
        return datetime(
            year=int(match.group(1)),
            month=int(match.group(2)),
            day=int(match.group(3)),
            hour=int(match.group(4)),
            minute=int(match.group(5)),
            tzinfo=KST,
        )

    @staticmethod
    def _normalize_code(value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _parse_float(value: object) -> float | None:
        if value is None:
            return None
        text = str(value).strip().replace("℃", "").replace("mm", "").replace("%", "").replace("m/s", "")
        if not text or text == "-":
            return None
        try:
            return float(text)
        except ValueError:
            return None

    @staticmethod
    def _parse_int(value: object) -> int | None:
        if value is None:
            return None
        text = str(value).strip().replace("%", "")
        if not text or text == "-":
            return None
        try:
            return int(float(text))
        except ValueError:
            return None

    @staticmethod
    def _clean_html(value: str) -> str:
        value = re.sub(r"<br\s*/?>", " ", value, flags=re.IGNORECASE)
        value = re.sub(r"<[^>]+>", "", value)
        return re.sub(r"\s+", " ", unescape(value)).strip()

    def _extract_html_value(self, html: str, pattern: str, *, source_name: str, response_text: str) -> str:
        match = re.search(pattern, html, flags=re.IGNORECASE | re.DOTALL)
        if not match:
            raise WeatherParseError(
                f"Fallback HTML selector did not match: {pattern}",
                source_name=source_name,
                response_text=response_text,
            )
        return self._clean_html(match.group(1))

    def _extract_icon_code(self, html: str) -> str | None:
        match = re.search(r'/weather/sky/([0-9]{2})\.png', html, flags=re.IGNORECASE)
        return match.group(1) if match else None
