BEGIN;

ALTER TABLE public.teams
    ADD COLUMN IF NOT EXISTS previous_regular_season_rank integer;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_teams_previous_regular_season_rank'
          AND conrelid = 'public.teams'::regclass
    ) THEN
        ALTER TABLE public.teams
            ADD CONSTRAINT chk_teams_previous_regular_season_rank
            CHECK (
                previous_regular_season_rank IS NULL
                OR previous_regular_season_rank BETWEEN 1 AND 10
            );
    END IF;
END $$;

UPDATE public.teams
SET previous_regular_season_rank = CASE
    WHEN code IN ('LG') THEN 1
    WHEN code IN ('HANWHA', 'HH') THEN 2
    WHEN code IN ('SSG', 'SK') THEN 3
    WHEN code IN ('SAMSUNG', 'SS') THEN 4
    WHEN code IN ('NC') THEN 5
    WHEN code IN ('KT') THEN 6
    WHEN code IN ('LOTTE', 'LT') THEN 7
    WHEN code IN ('KIA', 'HT') THEN 8
    WHEN code IN ('DOOSAN', 'DOO', 'OB') THEN 9
    WHEN code IN ('KIWOOM', 'WO') THEN 10
    ELSE previous_regular_season_rank
END
WHERE previous_regular_season_rank IS NULL;

COMMIT;
