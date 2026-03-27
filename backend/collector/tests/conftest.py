from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import pytest
import psycopg


TESTS_DIR = Path(__file__).resolve().parent
COLLECTOR_ROOT = TESTS_DIR.parent
if str(COLLECTOR_ROOT) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_ROOT))

from collector.db import connect


BASE_SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.teams (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code character varying(16) NOT NULL UNIQUE,
    name_ko character varying(50) NOT NULL,
    name_en character varying(50),
    short_name character varying(30) NOT NULL,
    theme_color character varying(16),
    logo_asset_name character varying(100),
    sort_order integer NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.games (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider character varying(30) NOT NULL,
    provider_game_id character varying(100) NOT NULL,
    game_date date NOT NULL,
    scheduled_at timestamptz,
    stadium character varying(100),
    status character varying(30) NOT NULL DEFAULT 'unknown',
    home_team_id uuid NOT NULL REFERENCES public.teams(id),
    away_team_id uuid NOT NULL REFERENCES public.teams(id),
    home_score integer NOT NULL DEFAULT 0,
    away_score integer NOT NULL DEFAULT 0,
    inning_state character varying(50),
    is_cancelled boolean NOT NULL DEFAULT false,
    is_postponed boolean NOT NULL DEFAULT false,
    source_updated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_games_home_away_different CHECK (home_team_id <> away_team_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_games_provider_provider_game_id
    ON public.games (provider, provider_game_id);

CREATE TABLE IF NOT EXISTS public.game_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    snapshot_at timestamptz NOT NULL,
    status character varying(30) NOT NULL DEFAULT 'unknown',
    inning_state character varying(50),
    home_score integer NOT NULL DEFAULT 0,
    away_score integer NOT NULL DEFAULT 0,
    payload_json jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_snapshots_game_id_snapshot_at
    ON public.game_snapshots (game_id, snapshot_at DESC);

CREATE TABLE IF NOT EXISTS public.device_registrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_token character varying(255) NOT NULL UNIQUE,
    platform character varying(30) NOT NULL DEFAULT 'ios',
    app_version character varying(50),
    device_id character varying(100),
    favorite_team_id uuid REFERENCES public.teams(id),
    notifications_enabled boolean NOT NULL DEFAULT true,
    last_seen_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_registrations_favorite_team_id
    ON public.device_registrations (favorite_team_id);

CREATE TABLE IF NOT EXISTS public.notification_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_registration_id uuid REFERENCES public.device_registrations(id) ON DELETE SET NULL,
    game_id uuid REFERENCES public.games(id) ON DELETE SET NULL,
    event_type character varying(50) NOT NULL,
    event_key character varying(255) NOT NULL,
    title character varying(200),
    body text,
    payload_json jsonb,
    sent_at timestamptz,
    delivery_status character varying(30) NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_events_event_key
    ON public.notification_events (event_key, device_registration_id);

CREATE INDEX IF NOT EXISTS idx_notification_events_game_id
    ON public.notification_events (game_id);
"""


MVP_MIGRATION_SQL = """
BEGIN;

ALTER TABLE public.games
    ADD COLUMN IF NOT EXISTS stadium_code varchar(8),
    ADD COLUMN IF NOT EXISTS official_provider_game_id varchar(64),
    ADD COLUMN IF NOT EXISTS provider_game_id_kind varchar(16) NOT NULL DEFAULT 'official';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_games_provider_game_id_kind'
          AND conrelid = 'public.games'::regclass
    ) THEN
        ALTER TABLE public.games
            ADD CONSTRAINT chk_games_provider_game_id_kind
            CHECK (provider_game_id_kind IN ('official', 'derived'));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_games_postponed_cancelled_exclusive'
          AND conrelid = 'public.games'::regclass
    ) THEN
        ALTER TABLE public.games
            ADD CONSTRAINT chk_games_postponed_cancelled_exclusive
            CHECK (NOT (is_postponed AND is_cancelled));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_games_provider_official_provider_game_id
    ON public.games (provider, official_provider_game_id)
    WHERE official_provider_game_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_games_stadium_code
    ON public.games (stadium_code);

CREATE INDEX IF NOT EXISTS idx_games_game_date_status
    ON public.games (game_date, status);

CREATE TABLE IF NOT EXISTS public.weather_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    observed_at timestamptz NOT NULL DEFAULT now(),
    source_name varchar(32) NOT NULL,
    stadium_code varchar(8) NOT NULL,
    current_icon_code varchar(8),
    current_icon_name varchar(64),
    current_temp_c numeric(4,1),
    current_rain_mm numeric(6,2),
    current_rain_raw varchar(32),
    current_humidity_pct integer,
    current_wind_speed_ms numeric(5,2),
    forecast_issued_at timestamptz,
    content_hash char(64) NOT NULL,
    payload_json jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_weather_snapshots_game_id_observed_at
    ON public.weather_snapshots (game_id, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_weather_snapshots_stadium_code_observed_at
    ON public.weather_snapshots (stadium_code, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_weather_snapshots_content_hash
    ON public.weather_snapshots (game_id, content_hash, observed_at DESC);

COMMIT;
"""


@pytest.fixture(scope="session")
def test_database_url() -> str:
    return os.getenv("TEST_DATABASE_URL", "postgresql://admin:adminkbo@postgres:5432/kbo_test")


@pytest.fixture(scope="session", autouse=True)
def ensure_test_database(test_database_url: str):
    admin_url = os.getenv("TEST_ADMIN_DATABASE_URL", "postgresql://admin:adminkbo@postgres:5432/postgres")

    db_name = test_database_url.rsplit("/", 1)[-1]

    with psycopg.connect(admin_url, autocommit=True) as admin_conn:
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

    with connect(test_database_url) as conn:
        with conn.cursor() as cur:
            cur.execute(BASE_SCHEMA_SQL)
            cur.execute(MVP_MIGRATION_SQL)
        conn.commit()
    yield


@pytest.fixture(scope="session")
def fixtures_root() -> Path:
    return TESTS_DIR / "fixtures"


@pytest.fixture
def db_connection_factory(test_database_url: str):
    def factory():
        return connect(test_database_url)

    return factory


@pytest.fixture
def test_logger(caplog: pytest.LogCaptureFixture) -> logging.Logger:
    caplog.set_level(logging.INFO)
    logger = logging.getLogger("collector.tests")
    logger.setLevel(logging.INFO)
    return logger


@pytest.fixture(autouse=True)
def clean_database(db_connection_factory):
    with db_connection_factory() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                TRUNCATE TABLE
                    notification_events,
                    weather_snapshots,
                    game_snapshots,
                    games,
                    device_registrations,
                    teams
                RESTART IDENTITY CASCADE
                """
            )
        conn.commit()
    yield
