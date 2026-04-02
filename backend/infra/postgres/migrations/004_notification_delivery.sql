BEGIN;

UPDATE public.notification_events
SET delivery_status = 'queued'
WHERE delivery_status = 'pending';

ALTER TABLE public.notification_events
    ALTER COLUMN delivery_status SET DEFAULT 'queued',
    ADD COLUMN IF NOT EXISTS attempted_at timestamptz,
    ADD COLUMN IF NOT EXISTS failed_at timestamptz,
    ADD COLUMN IF NOT EXISTS failure_reason varchar(255),
    ADD COLUMN IF NOT EXISTS attempt_count integer NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_notification_events_delivery_status'
          AND conrelid = 'public.notification_events'::regclass
    ) THEN
        ALTER TABLE public.notification_events
            ADD CONSTRAINT chk_notification_events_delivery_status
            CHECK (delivery_status IN ('queued', 'sent', 'failed'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_notification_events_delivery_status_created_at
    ON public.notification_events (delivery_status, created_at ASC, id ASC);

COMMIT;
