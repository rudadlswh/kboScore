from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class CollectorConfig:
    database_url: str
    log_level: str = "INFO"
    weather_scheduler_tick_seconds: int = 60
    live_poll_interval_seconds: int = 10
    db_wait_retry_seconds: int = 3
    http_timeout_seconds: int = 10
    parse_failure_artifact_dir: str = "artifacts"
    parse_failure_retention_days: int = 7

    @classmethod
    def from_env(cls) -> "CollectorConfig":
        database_url = os.environ["DATABASE_URL"]
        return cls(
            database_url=database_url,
            log_level=os.getenv("COLLECTOR_LOG_LEVEL", "INFO").upper(),
            weather_scheduler_tick_seconds=int(os.getenv("WEATHER_SCHEDULER_TICK_SECONDS", "60")),
            live_poll_interval_seconds=int(os.getenv("LIVE_POLL_INTERVAL_SECONDS", "10")),
            db_wait_retry_seconds=int(os.getenv("DB_WAIT_RETRY_SECONDS", "3")),
            http_timeout_seconds=int(os.getenv("HTTP_TIMEOUT_SECONDS", "10")),
            parse_failure_artifact_dir=os.getenv("PARSE_FAILURE_ARTIFACT_DIR", "artifacts"),
            parse_failure_retention_days=int(os.getenv("PARSE_FAILURE_RETENTION_DAYS", "7")),
        )
