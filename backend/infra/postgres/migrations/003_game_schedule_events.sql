BEGIN;

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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_game_schedule_events_event_type'
          AND conrelid = 'public.game_schedule_events'::regclass
    ) THEN
        ALTER TABLE public.game_schedule_events
            ADD CONSTRAINT chk_game_schedule_events_event_type
            CHECK (event_type IN (
                'postponed_candidate',
                'postponed_confirmed',
                'doubleheader_announced',
                'makeup_scheduled',
                'venue_changed',
                'time_changed',
                'status_corrected'
            ));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_game_schedule_events_event_key
    ON public.game_schedule_events (event_key);

CREATE INDEX IF NOT EXISTS idx_game_schedule_events_game_id_recorded_at
    ON public.game_schedule_events (game_id, recorded_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_game_schedule_events_recorded_at
    ON public.game_schedule_events (recorded_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_game_schedule_events_event_type
    ON public.game_schedule_events (event_type, recorded_at DESC);

COMMIT;
