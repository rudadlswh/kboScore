from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest
import psycopg
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker


API_ROOT = Path(__file__).resolve().parents[1]
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from app.db.session import get_db, get_sqlalchemy_database_url
from app.main import app

TEST_SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.teams (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code character varying(16) NOT NULL UNIQUE,
    name_ko character varying(50) NOT NULL,
    name_en character varying(50),
    short_name character varying(30) NOT NULL,
    previous_regular_season_rank integer,
    sort_order integer NOT NULL,
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.games (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider character varying(30) NOT NULL,
    provider_game_id character varying(100) NOT NULL,
    official_provider_game_id varchar(64),
    game_date date NOT NULL,
    scheduled_at timestamptz,
    stadium character varying(100),
    stadium_code varchar(8),
    status character varying(30) NOT NULL DEFAULT 'unknown',
    season_classification varchar(32) NOT NULL DEFAULT 'unknown',
    home_team_id uuid NOT NULL REFERENCES public.teams(id),
    away_team_id uuid NOT NULL REFERENCES public.teams(id),
    home_score integer NOT NULL DEFAULT 0,
    away_score integer NOT NULL DEFAULT 0,
    inning_state character varying(50),
    is_cancelled boolean NOT NULL DEFAULT false,
    is_postponed boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.game_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    snapshot_at timestamptz NOT NULL,
    status character varying(30) NOT NULL DEFAULT 'unknown',
    inning_state character varying(50),
    home_score integer NOT NULL DEFAULT 0,
    away_score integer NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.weather_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    observed_at timestamptz NOT NULL DEFAULT now(),
    source_name varchar(32) NOT NULL,
    stadium_code varchar(8) NOT NULL,
    current_icon_name varchar(64),
    current_temp_c numeric(4,1),
    current_rain_mm numeric(6,2),
    content_hash char(64) NOT NULL DEFAULT repeat('0', 64),
    payload_json jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_game_snapshots_game_id_snapshot_at
    ON public.game_snapshots (game_id, snapshot_at DESC);

CREATE INDEX IF NOT EXISTS idx_weather_snapshots_stadium_code_observed_at
    ON public.weather_snapshots (stadium_code, observed_at DESC);

CREATE TABLE IF NOT EXISTS public.game_schedule_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    event_type varchar(64) NOT NULL,
    confirmed boolean NOT NULL DEFAULT false,
    reason varchar(64),
    source varchar(64) NOT NULL,
    recorded_at timestamptz NOT NULL,
    payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    event_key char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_schedule_events_event_key
    ON public.game_schedule_events (event_key);

CREATE INDEX IF NOT EXISTS idx_game_schedule_events_game_id_recorded_at
    ON public.game_schedule_events (game_id, recorded_at DESC, id DESC);
"""


@pytest.fixture(scope="session")
def api_test_database_url() -> str:
    return os.getenv("API_TEST_DATABASE_URL", os.getenv("TEST_DATABASE_URL", "postgresql://admin:adminkbo@127.0.0.1:55432/kbo_api_test"))


@pytest.fixture(scope="session")
def api_test_admin_database_url() -> str:
    return os.getenv(
        "API_TEST_ADMIN_DATABASE_URL",
        os.getenv("TEST_ADMIN_DATABASE_URL", "postgresql://admin:adminkbo@127.0.0.1:55432/postgres"),
    )


@pytest.fixture(scope="session", autouse=True)
def ensure_api_test_database(api_test_database_url: str, api_test_admin_database_url: str):
    db_name = api_test_database_url.rsplit("/", 1)[-1]

    with psycopg.connect(api_test_admin_database_url, autocommit=True) as admin_conn:
        with admin_conn.cursor() as cur:
            cur.execute(
                """
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s
                  AND pid <> pg_backend_pid()
                """,
                (db_name,),
            )
            cur.execute(f'DROP DATABASE IF EXISTS "{db_name}"')
            cur.execute(f'CREATE DATABASE "{db_name}"')

    engine = create_engine(get_sqlalchemy_database_url(api_test_database_url), pool_pre_ping=True)
    with engine.begin() as conn:
        for statement in TEST_SCHEMA_SQL.split(";"):
            if statement.strip():
                conn.execute(text(statement))
    engine.dispose()
    yield


@pytest.fixture(scope="session")
def api_engine(api_test_database_url: str):
    engine = create_engine(get_sqlalchemy_database_url(api_test_database_url), pool_pre_ping=True)
    yield engine
    engine.dispose()


@pytest.fixture
def db_session(api_engine) -> Session:
    session_factory = sessionmaker(bind=api_engine, autoflush=False, autocommit=False, class_=Session)
    session = session_factory()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(autouse=True)
def clean_api_database(api_engine):
    with api_engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE game_schedule_events, weather_snapshots, game_snapshots, games, teams RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture
def client():
    def _get_test_db():
        return object()

    app.dependency_overrides[get_db] = _get_test_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def db_client(db_session: Session):
    def _get_test_db():
        try:
            yield db_session
        finally:
            db_session.rollback()

    app.dependency_overrides[get_db] = _get_test_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
