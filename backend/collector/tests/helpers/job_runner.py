from __future__ import annotations

import json
import logging
from collections import defaultdict
from datetime import datetime
from typing import Any

from collector.jobs.confirmed_rainout_notify_job import (
    ConfirmedRainoutNotifyJob,
    ConfirmedRainoutNotifyJobDependencies,
    ConfirmedRainoutNotifyJobInput,
)
from collector.jobs.notification_delivery_job import (
    NotificationDeliveryJob,
    NotificationDeliveryJobDependencies,
    NotificationDeliveryJobInput,
)
from collector.jobs.live_score_poll_job import (
    LiveScorePollJob,
    LiveScorePollJobDependencies,
    LiveScorePollJobInput,
)
from collector.jobs.schedule_bootstrap_job import (
    ScheduleBootstrapJob,
    ScheduleBootstrapJobDependencies,
    ScheduleBootstrapJobInput,
)
from collector.jobs.weather_poll_job import (
    WeatherPollJob,
    WeatherPollJobDependencies,
    WeatherPollJobInput,
)
from collector.services.apns_client import APNSClient
from collector.services.kbo_schedule_source import KBOScheduleSource, ScheduleSourceRequest
from collector.services.kbo_scoreboard_source import KBOScoreboardSource
from collector.services.kbo_weather_source import KBOWeatherSource
from collector.utils.http import HTTPResponse
from tests.helpers.fixture_loader import load_json_fixture, load_text_fixture


class ScriptedHTTPClient:
    def __init__(self) -> None:
        self._responses: dict[tuple[str, str], list[HTTPResponse]] = defaultdict(list)

    def add_text_response(self, method: str, url: str, body_text: str, status_code: int = 200) -> None:
        self._responses[(method.upper(), url)].append(
            HTTPResponse(status_code=status_code, headers={}, body=body_text.encode("utf-8"))
        )

    def add_json_response(self, method: str, url: str, payload: Any, status_code: int = 200) -> None:
        self.add_text_response(method, url, json.dumps(payload, ensure_ascii=False), status_code=status_code)

    def get(self, url: str, headers: dict[str, str] | None = None) -> HTTPResponse:
        return self._pop("GET", url)

    def post(self, url: str, form_data: dict[str, str], headers: dict[str, str] | None = None) -> HTTPResponse:
        return self._pop("POST", url)

    def _pop(self, method: str, url: str) -> HTTPResponse:
        key = (method.upper(), url)
        if not self._responses[key]:
            raise AssertionError(f"No scripted HTTP response available for {method} {url}")
        return self._responses[key].pop(0)


def build_schedule_source(
    *,
    primary_fixture: str | None = None,
    fallback_fixture: str | None = None,
) -> KBOScheduleSource:
    http_client = ScriptedHTTPClient()
    if primary_fixture is not None:
        http_client.add_json_response("POST", KBOScheduleSource.PRIMARY_URL, load_json_fixture(*primary_fixture.split("/")))
    if fallback_fixture is not None:
        request = ScheduleSourceRequest(season_id=2026, month=3)
        series_id_list = KBOScheduleSource.series_id_list_for_request(request)
        http_client.add_text_response(
            "GET",
            KBOScheduleSource.FALLBACK_URL + f"?seriesId={series_id_list}&date=20260301",
            load_text_fixture(*fallback_fixture.split("/")),
        )
    return KBOScheduleSource(http_client=http_client)


def build_weather_source(
    *,
    weather_fixture: str | None = None,
    weather_html_fixture: str | None = None,
    today_games_fixture: str | None = None,
) -> KBOWeatherSource:
    http_client = ScriptedHTTPClient()
    if weather_fixture is not None:
        http_client.add_json_response("POST", KBOWeatherSource.WEATHER_URL, load_json_fixture(*weather_fixture.split("/")))
    if weather_html_fixture is not None:
        http_client.add_text_response("GET", KBOWeatherSource.WEATHER_PAGE_URL + "?stadium=JS&leId=1", load_text_fixture(*weather_html_fixture.split("/")))
    if today_games_fixture is not None:
        http_client.add_json_response("POST", KBOWeatherSource.TODAY_GAMES_URL, load_json_fixture(*today_games_fixture.split("/")))
    return KBOWeatherSource(http_client=http_client)


def build_live_source(
    *,
    scoreboard_html_fixture: str,
    ajax_fixture: str | None = None,
) -> KBOScoreboardSource:
    http_client = ScriptedHTTPClient()
    http_client.add_text_response("GET", KBOScoreboardSource.SCOREBOARD_URL, load_text_fixture(*scoreboard_html_fixture.split("/")))
    if ajax_fixture is not None:
        http_client.add_json_response("POST", KBOScoreboardSource.LIVE_LIST_URL, load_json_fixture(*ajax_fixture.split("/")))
    return KBOScoreboardSource(http_client=http_client)


def run_schedule_bootstrap_job(
    *,
    db_connection_factory,
    logger: logging.Logger,
    schedule_source: KBOScheduleSource,
    scoreboard_source: KBOScoreboardSource | None = None,
    season_id: int,
    months: list[int],
):
    job = ScheduleBootstrapJob(
        ScheduleBootstrapJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory,
            schedule_source=schedule_source,
            scoreboard_source=scoreboard_source,
        )
    )
    return job.execute(ScheduleBootstrapJobInput(season_id=season_id, months=months))


def run_weather_poll_job(
    *,
    db_connection_factory,
    logger: logging.Logger,
    weather_source: KBOWeatherSource,
    now_at: datetime,
):
    job = WeatherPollJob(
        WeatherPollJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory,
            weather_source=weather_source,
            artifact_dir="artifacts/test",
        )
    )
    return job.execute(WeatherPollJobInput(now_at=now_at))


def run_live_poll_job(
    *,
    db_connection_factory,
    logger: logging.Logger,
    live_source: KBOScoreboardSource,
    now_at: datetime,
):
    job = LiveScorePollJob(
        LiveScorePollJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory,
            scoreboard_source=live_source,
            artifact_dir="artifacts/test",
        )
    )
    return job.execute(LiveScorePollJobInput(now_at=now_at))


def run_confirmed_rainout_notify_job(
    *,
    db_connection_factory,
    logger: logging.Logger,
    now_at: datetime,
):
    job = ConfirmedRainoutNotifyJob(
        ConfirmedRainoutNotifyJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory,
        )
    )
    return job.execute(ConfirmedRainoutNotifyJobInput(now_at=now_at))


def run_notification_delivery_job(
    *,
    db_connection_factory,
    logger: logging.Logger,
    apns_client: APNSClient,
    now_at: datetime,
    batch_size: int = 100,
    max_attempts: int = 3,
    retry_delays_seconds: tuple[int, ...] = (60, 300),
):
    job = NotificationDeliveryJob(
        NotificationDeliveryJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory,
            apns_client=apns_client,
        )
    )
    return job.execute(
        NotificationDeliveryJobInput(
            now_at=now_at,
            batch_size=batch_size,
            max_attempts=max_attempts,
            retry_delays_seconds=retry_delays_seconds,
        )
    )
