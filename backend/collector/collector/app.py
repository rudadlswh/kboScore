from __future__ import annotations

import time

from collector.config import CollectorConfig
from collector.db import wait_for_db
from collector.utils.logging import configure_logging, get_logger


def main() -> None:
    """Collector entrypoint for the MVP skeleton."""
    config = CollectorConfig.from_env()
    configure_logging(config.log_level)
    logger = get_logger(__name__)

    wait_for_db(config.database_url, logger=logger)
    logger.info(
        "collector_started",
        extra={
            "weather_tick_seconds": config.weather_scheduler_tick_seconds,
            "live_poll_seconds": config.live_poll_interval_seconds,
        },
    )

    # TODO: wire the scheduler loops to the concrete jobs after source verification and parser work.
    while True:
        logger.info("collector_idle")
        time.sleep(30)


if __name__ == "__main__":
    main()
