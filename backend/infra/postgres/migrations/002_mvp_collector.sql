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
