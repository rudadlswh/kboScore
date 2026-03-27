from __future__ import annotations

import logging
import time
from contextlib import contextmanager
from hashlib import sha256
from typing import Iterator

import psycopg
from psycopg.rows import dict_row


def connect(database_url: str) -> psycopg.Connection:
    return psycopg.connect(database_url, row_factory=dict_row)


def wait_for_db(database_url: str, logger: logging.Logger, retry_seconds: int = 3) -> None:
    while True:
        try:
            with connect(database_url) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
            logger.info("database_ready")
            return
        except Exception as error:  # pragma: no cover - integration-time behavior
            logger.warning("database_waiting", extra={"error": str(error)})
            time.sleep(retry_seconds)


def advisory_lock_key(lock_name: str) -> int:
    digest = sha256(lock_name.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], byteorder="big", signed=False) & 0x7FFFFFFFFFFFFFFF


def try_advisory_lock(conn: psycopg.Connection, lock_name: str) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT pg_try_advisory_lock(%s)", (advisory_lock_key(lock_name),))
        row = cur.fetchone()
    return bool(row["pg_try_advisory_lock"])  # type: ignore[index]


def advisory_unlock(conn: psycopg.Connection, lock_name: str) -> None:
    with conn.cursor() as cur:
        cur.execute("SELECT pg_advisory_unlock(%s)", (advisory_lock_key(lock_name),))


@contextmanager
def advisory_lock(conn: psycopg.Connection, lock_name: str) -> Iterator[bool]:
    locked = try_advisory_lock(conn, lock_name)
    try:
        yield locked
    finally:
        if locked:
            advisory_unlock(conn, lock_name)
