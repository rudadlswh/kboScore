from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class CollectorConfig:
    database_url: str
    log_level: str = "INFO"
    weather_scheduler_tick_seconds: int = 60
    live_poll_interval_seconds: int = 10
    live_poll_enabled: bool = False
    notification_delivery_enabled: bool = False
    notification_delivery_interval_seconds: int = 30
    db_wait_retry_seconds: int = 3
    http_timeout_seconds: int = 10
    parse_failure_artifact_dir: str = "artifacts"
    parse_failure_retention_days: int = 7
    notification_delivery_batch_size: int = 100
    notification_delivery_max_attempts: int = 3
    notification_retry_delays_seconds: tuple[int, ...] = (60, 300)
    apns_team_id: str | None = None
    apns_key_id: str | None = None
    apns_bundle_id: str | None = None
    apns_private_key_path: str | None = None
    apns_use_sandbox: bool = True

    @classmethod
    def from_env(cls) -> "CollectorConfig":
        database_url = os.environ["DATABASE_URL"]
        return cls(
            database_url=database_url,
            log_level=os.getenv("COLLECTOR_LOG_LEVEL", "INFO").upper(),
            weather_scheduler_tick_seconds=int(os.getenv("WEATHER_SCHEDULER_TICK_SECONDS", "60")),
            live_poll_interval_seconds=int(os.getenv("LIVE_POLL_INTERVAL_SECONDS", "10")),
            live_poll_enabled=os.getenv("LIVE_POLL_ENABLED", "true").lower() in {"1", "true", "yes", "on"},
            notification_delivery_enabled=os.getenv("NOTIFICATION_DELIVERY_ENABLED", "false").lower()
            in {"1", "true", "yes", "on"},
            notification_delivery_interval_seconds=int(os.getenv("NOTIFICATION_DELIVERY_INTERVAL_SECONDS", "30")),
            db_wait_retry_seconds=int(os.getenv("DB_WAIT_RETRY_SECONDS", "3")),
            http_timeout_seconds=int(os.getenv("HTTP_TIMEOUT_SECONDS", "10")),
            parse_failure_artifact_dir=os.getenv("PARSE_FAILURE_ARTIFACT_DIR", "artifacts"),
            parse_failure_retention_days=int(os.getenv("PARSE_FAILURE_RETENTION_DAYS", "7")),
            notification_delivery_batch_size=int(os.getenv("NOTIFICATION_DELIVERY_BATCH_SIZE", "100")),
            notification_delivery_max_attempts=int(os.getenv("NOTIFICATION_DELIVERY_MAX_ATTEMPTS", "3")),
            notification_retry_delays_seconds=tuple(
                int(value.strip())
                for value in os.getenv("NOTIFICATION_RETRY_DELAYS_SECONDS", "60,300").split(",")
                if value.strip()
            ),
            apns_team_id=os.getenv("APNS_TEAM_ID"),
            apns_key_id=os.getenv("APNS_KEY_ID"),
            apns_bundle_id=os.getenv("APNS_BUNDLE_ID"),
            apns_private_key_path=os.getenv("APNS_PRIVATE_KEY_PATH"),
            apns_use_sandbox=os.getenv("APNS_USE_SANDBOX", "true").lower() in {"1", "true", "yes", "on"},
        )
