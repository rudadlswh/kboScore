from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
import time
from typing import Callable

from collector.config import CollectorConfig
from collector.db import connect, wait_for_db
from collector.jobs.live_score_poll_job import (
    LiveScorePollJob,
    LiveScorePollJobDependencies,
    LiveScorePollJobInput,
)
from collector.jobs.notification_delivery_job import (
    NotificationDeliveryJob,
    NotificationDeliveryJobDependencies,
    NotificationDeliveryJobInput,
    NotificationDeliveryJobSummary,
)
from collector.services.apns_client import APNSConfigurationError, TokenBasedAPNSClient
from collector.services.kbo_scoreboard_source import KBOScoreboardSource
from collector.utils.logging import configure_logging, get_logger
from collector.utils.time import now_kst, to_kst


@dataclass(slots=True)
class CollectorRuntimeState:
    live_score_poll_job: LiveScorePollJob | None = None
    next_live_score_poll_at: datetime | None = None
    notification_delivery_job: NotificationDeliveryJob | None = None
    next_notification_delivery_at: datetime | None = None


def build_runtime_state(
    *,
    config: CollectorConfig,
    logger,
    db_connection_factory: Callable[[], object] | None = None,
) -> CollectorRuntimeState:
    live_score_poll_job: LiveScorePollJob | None = None
    next_live_score_poll_at: datetime | None = None
    if config.live_poll_enabled:
        live_score_poll_job = LiveScorePollJob(
            LiveScorePollJobDependencies(
                logger=logger,
                db_connection_factory=db_connection_factory or (lambda: connect(config.database_url)),
                scoreboard_source=KBOScoreboardSource(),
                artifact_dir=config.parse_failure_artifact_dir,
            )
        )
        next_live_score_poll_at = now_kst()
        logger.info(
            "live_score_poll_scheduler_enabled",
            extra={
                "interval_seconds": config.live_poll_interval_seconds,
                "artifact_dir": config.parse_failure_artifact_dir,
            },
        )
    else:
        logger.info("live_score_poll_scheduler_disabled")

    if not config.notification_delivery_enabled:
        logger.info("notification_delivery_scheduler_disabled")
        return CollectorRuntimeState(
            live_score_poll_job=live_score_poll_job,
            next_live_score_poll_at=next_live_score_poll_at,
        )

    apns_client = TokenBasedAPNSClient.from_config(config)
    delivery_job = NotificationDeliveryJob(
        NotificationDeliveryJobDependencies(
            logger=logger,
            db_connection_factory=db_connection_factory or (lambda: connect(config.database_url)),
            apns_client=apns_client,
        )
    )
    logger.info(
        "notification_delivery_scheduler_enabled",
        extra={
            "interval_seconds": config.notification_delivery_interval_seconds,
            "batch_size": config.notification_delivery_batch_size,
            "max_attempts": config.notification_delivery_max_attempts,
            "use_sandbox": config.apns_use_sandbox,
        },
    )
    return CollectorRuntimeState(
        live_score_poll_job=live_score_poll_job,
        next_live_score_poll_at=next_live_score_poll_at,
        notification_delivery_job=delivery_job,
        next_notification_delivery_at=now_kst(),
    )


def run_runtime_tick(
    *,
    state: CollectorRuntimeState,
    config: CollectorConfig,
    logger,
    now_at: datetime | None = None,
) -> NotificationDeliveryJobSummary | None:
    observed_at = to_kst(now_at or now_kst())

    if state.live_score_poll_job is not None:
        if state.next_live_score_poll_at is None or observed_at >= state.next_live_score_poll_at:
            logger.info(
                "live_score_poll_tick_started",
                extra={
                    "job_name": state.live_score_poll_job.job_name,
                    "now_at": observed_at.isoformat(),
                },
            )
            summary = state.live_score_poll_job.run_with_retry(LiveScorePollJobInput(now_at=observed_at))
            state.next_live_score_poll_at = observed_at + timedelta(seconds=config.live_poll_interval_seconds)
            logger.info(
                "live_score_poll_tick_finished",
                extra={
                    "job_name": state.live_score_poll_job.job_name,
                    "candidate_games": summary.candidate_games,
                    "polled_games": summary.polled_games,
                    "inserted_snapshots": summary.inserted_snapshots,
                    "canonical_updates": summary.canonical_updates,
                    "parse_failures": summary.parse_failures,
                },
            )

    if state.notification_delivery_job is None:
        return None

    if state.next_notification_delivery_at is not None and observed_at < state.next_notification_delivery_at:
        return None

    logger.info(
        "notification_delivery_tick_started",
        extra={
            "job_name": state.notification_delivery_job.job_name,
            "now_at": observed_at.isoformat(),
        },
    )
    summary = state.notification_delivery_job.execute(
        NotificationDeliveryJobInput(
            now_at=observed_at,
            batch_size=config.notification_delivery_batch_size,
            max_attempts=config.notification_delivery_max_attempts,
            retry_delays_seconds=config.notification_retry_delays_seconds,
        )
    )
    state.next_notification_delivery_at = observed_at + timedelta(seconds=config.notification_delivery_interval_seconds)
    logger.info(
        "notification_delivery_tick_finished",
        extra={
            "job_name": state.notification_delivery_job.job_name,
            "selected_rows": summary.selected_rows,
            "attempted_rows": summary.attempted_rows,
            "sent_rows": summary.sent_rows,
            "failed_rows": summary.failed_rows,
        },
    )
    return summary


def main() -> None:
    """Collector runtime entrypoint."""
    config = CollectorConfig.from_env()
    configure_logging(config.log_level)
    logger = get_logger(__name__)

    wait_for_db(config.database_url, logger=logger)
    try:
        runtime_state = build_runtime_state(config=config, logger=logger)
    except APNSConfigurationError:
        logger.exception("notification_delivery_scheduler_configuration_error")
        raise

    logger.info(
        "collector_started",
        extra={
            "weather_tick_seconds": config.weather_scheduler_tick_seconds,
            "live_poll_seconds": config.live_poll_interval_seconds,
            "notification_delivery_enabled": config.notification_delivery_enabled,
            "notification_delivery_interval_seconds": config.notification_delivery_interval_seconds,
        },
    )

    # TODO: wire the scheduler loops to the concrete jobs after source verification and parser work.
    while True:
        run_runtime_tick(state=runtime_state, config=config, logger=logger)
        time.sleep(1 if config.notification_delivery_enabled else 30)


if __name__ == "__main__":
    main()
