BEGIN;

ALTER TABLE public.notification_events
    ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_notification_events_delivery_retry
    ON public.notification_events (delivery_status, next_attempt_at ASC, created_at ASC, id ASC);

COMMIT;
