BEGIN;

ALTER TABLE public.games
    ADD COLUMN IF NOT EXISTS season_classification varchar(32) NOT NULL DEFAULT 'unknown';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_games_season_classification'
          AND conrelid = 'public.games'::regclass
    ) THEN
        ALTER TABLE public.games
            ADD CONSTRAINT chk_games_season_classification
            CHECK (season_classification IN (
                'unknown',
                'regular_season',
                'exhibition_preseason',
                'postseason'
            ));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_games_game_date_season_classification
    ON public.games (game_date, season_classification);

COMMIT;
