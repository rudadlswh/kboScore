from __future__ import annotations

import gzip
import logging
from pathlib import Path

from collector.utils.hash import sha256_bytes_hexdigest
from collector.utils.time import fifteen_minute_bucket, to_kst


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


def capture_parse_failure_artifact(
    *,
    base_dir: str,
    job_name: str,
    source_name: str,
    game_id: str,
    observed_at,
    response_text: str | None,
) -> tuple[str | None, str]:
    observed_at = to_kst(observed_at)
    bucket = fifteen_minute_bucket(observed_at)
    response_bytes = (response_text or "").encode("utf-8", errors="replace")
    response_hash = sha256_bytes_hexdigest(response_bytes)
    if not response_bytes:
        return None, response_hash

    day_dir = (
        Path(base_dir)
        / observed_at.strftime("%Y")
        / observed_at.strftime("%m")
        / observed_at.strftime("%d")
        / job_name
    )
    day_dir.mkdir(parents=True, exist_ok=True)
    artifact_path = day_dir / f"{game_id}_{source_name}_{bucket.strftime('%Y%m%d%H%M')}.txt.gz"
    if not artifact_path.exists():
        with gzip.open(artifact_path, "wb") as file_obj:
            file_obj.write(response_bytes)
    return str(artifact_path), response_hash


def log_parse_failure(
    logger: logging.Logger,
    *,
    job_name: str,
    source_name: str,
    game_id: str,
    provider_game_id: str,
    game_date: str,
    observed_at: str,
    error_class: str,
    error_message: str,
    artifact_path: str | None,
    response_hash: str,
) -> None:
    logger.error(
        "parse_failure",
        extra={
            "job_name": job_name,
            "source_name": source_name,
            "game_id": game_id,
            "provider_game_id": provider_game_id,
            "game_date": game_date,
            "observed_at": observed_at,
            "error_class": error_class,
            "error_message": error_message,
            "artifact_path": artifact_path,
            "response_hash": response_hash,
        },
    )
