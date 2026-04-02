# Backend Testing

## Purpose

The collector integration tests exercise the MVP collection pipeline end to end against fixture-backed source payloads and a real PostgreSQL database. They exist to catch regressions in:

- season schedule bootstrap
- same-day weather polling
- same-day live scoreboard polling
- confirmed rainout `notification_events` creation

The golden fixture set under `backend/collector/tests/fixtures/` gives the tests stable source payloads so they remain reproducible locally and in CI.

## Prerequisites

- Docker with `docker compose`
- Python 3.10+

The local command uses the Postgres service defined in `backend/docker-compose.yml`. It creates and resets a dedicated `kbo_test` database automatically through the pytest harness in `backend/collector/tests/conftest.py`.

The script prefers `python3.12`, then `python3.11`, then `python3.10`. Override with `PYTHON_BIN=...` if your local interpreter lives elsewhere.

If `backend/.env` is missing, copy `backend/.env.example` first.

## Official local command

From the repo root:

```bash
make test-integration
```

The target calls `backend/scripts/test_integration.sh`, which:

1. starts the local Postgres container
2. creates a local Python test virtualenv at `backend/collector/.venv-test`
3. installs collector runtime deps plus `pytest`
4. runs `backend/collector/tests/integration`

To run a single file:

```bash
./backend/scripts/test_integration.sh tests/integration/test_live_poll.py
```

## Environment

The local script derives these defaults from `backend/.env` or `backend/.env.example`:

- `LOCAL_TEST_POSTGRES_PORT=55432`
- `TEST_DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/kbo_test`
- `TEST_ADMIN_DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/postgres`

Override them only if your local Postgres test endpoint differs.

## What CI validates

GitHub Actions runs the same fixture-backed integration tests on:

- every pull request
- every push to `main`

CI provisions PostgreSQL as a GitHub Actions service container and runs:

```bash
python -m pytest tests/integration -q
```

No production secrets are required.

## Common failure causes

- Postgres is not reachable on `127.0.0.1:${LOCAL_TEST_POSTGRES_PORT:-55432}`
- `backend/.env` has drifted from the local Docker Compose credentials
- fixture content no longer matches the current source adapter selectors
- a test changed fixture expectations without updating the corresponding golden payload

## Debugging checkpoints

- Confirm Postgres is healthy:

```bash
docker compose -f backend/docker-compose.yml ps postgres
```

- Re-run one test file:

```bash
./backend/scripts/test_integration.sh tests/integration/test_weather_poll.py
```

- Inspect the golden fixtures used by the tests:

```bash
find backend/collector/tests/fixtures -type f | sort
```

- Review parse-failure artifacts if a parser starts failing:
  - `backend/collector/artifacts/`

## Local vs CI differences

- Local: uses the Docker Compose Postgres service from `backend/docker-compose.yml`
- CI: uses a GitHub Actions Postgres service container
- Both: run the same pytest integration suite and rely on the same golden fixtures

The collector business logic is intentionally not mocked beyond the scripted HTTP fixture responses already used by the test helpers.

# Backend API

## Read-only contract

The FastAPI service under `backend/api` is read-only.

- It serves canonical rows and snapshots already produced by the collector.
- It does not crawl, normalize, or perform state transitions itself.
- Collector remains the owner of source parsing, normalization, and canonical game state updates.

## MVP endpoints

- `GET /v1/health`
- `GET /v1/teams`
- `GET /v1/games?date=YYYY-MM-DD&teamId=&status=`
- `GET /v1/games/{gameId}`
- `GET /v1/games/{gameId}/snapshots?limit=`
- `GET /v1/games/{gameId}/weather`
- `GET /v1/teams/{teamId}/games?dateFrom=YYYY-MM-DD&dateTo=YYYY-MM-DD&status=`
- `GET /v1/games/{gameId}/events`
- `GET /v1/events?date=YYYY-MM-DD&teamId=&eventType=`

## Canonical game event history

`notification_events` is not authoritative game history.

- It exists only as a push dedupe / delivery ledger.
- It must stay separate from collector-owned canonical game state history.

Authoritative per-game event history now lives in `game_schedule_events`.

Core columns:

- `id`
- `game_id`
- `event_type`
- `confirmed`
- `reason`
- `source`
- `recorded_at`
- `payload_json`
- `event_key`
- `created_at`

Canonical vs trace fields:

- Canonical read-side fields:
  - `event_type`
  - `confirmed`
  - `reason`
  - `recorded_at`
- Source-trace/debug fields:
  - `source`
  - `payload_json`
  - `event_key`

Current supported event types:

- `postponed_candidate`
- `postponed_confirmed`
- `doubleheader_announced`
- `makeup_scheduled`
- `venue_changed`
- `time_changed`
- `status_corrected`

Collector write rules:

- Event history is append-only.
- Duplicate effective events are prevented by deterministic `event_key`.
- `recorded_at` is the observed event time from the collector in KST-aware datetime form.
- Current collector hooks only write events the pipeline can already determine conservatively:
  - confirmed postponements from official weather/live status updates
  - schedule bootstrap time/venue/status corrections
- `postponed_candidate` is supported by schema/service contract, but the current collector does not emit it automatically yet because there is no strong candidate-only signal wired into the canonical flow.

## Notification generation

Notification generation now consumes canonical `game_schedule_events` and writes outbound rows to `notification_events`.

- `game_schedule_events`: authoritative historical fact stream
- `notification_events`: deduped outbound notification ledger

Current favorite-team integration point:

- `device_registrations.favorite_team_id`
- A device is notification-eligible when:
  - `notifications_enabled = true`
  - `device_token` is not blank
  - `favorite_team_id` matches either the home or away team for the event's game

Current event types that generate notifications:

- `postponed_confirmed`
- `time_changed`
- `venue_changed`

Current non-notifiable event handling:

- `status_corrected` remains in canonical history, but does not emit notifications yet unless a later source mapping proves a user-impacting correction path worth notifying conservatively.
- `postponed_candidate`, `doubleheader_announced`, and `makeup_scheduled` are schema-supported, but not auto-emitted by the collector today.

Idempotency and dedupe:

- The collector scans recent canonical `game_schedule_events` rows.
- Each canonical event already has a deterministic semantic `event_key`.
- Notification generation derives `notification_events.event_key` from that canonical event key.
- The existing unique constraint on `(event_key, device_registration_id)` guarantees per-device idempotency across reruns.

Delivery boundary:

- Delivery sending now consumes queued `notification_events` rows and updates them to:
  - `queued`
  - `sent`
  - `failed`
- Additive delivery metadata on `notification_events`:
  - `attempted_at`
  - `sent_at`
  - `failed_at`
  - `failure_reason`
  - `attempt_count`
  - `next_attempt_at`
- APNs sending is intentionally separate from history generation:
  - `game_schedule_events` stays authoritative history
  - `notification_events` stays delivery state only
- `notification_events` remains an outbound ledger and does not become authoritative game history.

APNs configuration:

- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`
- `APNS_USE_SANDBOX=true|false`
- `NOTIFICATION_DELIVERY_ENABLED=true|false`
- `NOTIFICATION_DELIVERY_INTERVAL_SECONDS` default `30`
- `NOTIFICATION_DELIVERY_BATCH_SIZE` default `100`
- `NOTIFICATION_DELIVERY_MAX_ATTEMPTS` default `3`
- `NOTIFICATION_RETRY_DELAYS_SECONDS` default `60,300`

Delivery scheduler wiring:

- The collector runtime now wires `notification_delivery_job` into `backend/collector/collector/app.py`.
- The scheduler uses the existing collector process loop and keeps the job's advisory lock / bounded batch behavior unchanged.
- Startup behavior:
  - when `NOTIFICATION_DELIVERY_ENABLED=false`, delivery stays disabled and startup remains a safe no-op
  - when `NOTIFICATION_DELIVERY_ENABLED=true`, APNs configuration is validated immediately at startup
  - missing APNs config fails fast at startup instead of silently leaving queued rows unsent
- Runtime logs include:
  - delivery scheduler enabled/disabled at startup
  - delivery tick started
  - delivery tick finished with `selected_rows`, `attempted_rows`, `sent_rows`, `failed_rows`

Current delivery behavior:

- The delivery job selects:
  - newly `queued` rows
  - retryable `failed` rows whose `next_attempt_at` is due
- Rows already marked `sent` are not sent again.
- Rows marked `failed` are:
  - retryable when `next_attempt_at` is set
  - terminal when `next_attempt_at` is null
- Blank tokens, missing device rows, and disabled device rows are marked `failed` with explicit reasons.
- Current retryable failure classes:
  - APNs transport errors
  - APNs timeouts
  - APNs 5xx responses
  - APNs 429 responses
- Current terminal failure classes:
  - `missing_device_registration`
  - `notifications_disabled`
  - `missing_device_token`
  - `blank_device_token`
  - APNs invalid/unregistered token style failures such as `BadDeviceToken`, `Unregistered`, `DeviceTokenNotForTopic`
- Invalid/unregistered token style failures also disable `device_registrations.notifications_enabled` for that device row.
- Operational backlog handling remains DB/runbook based; there is no admin API for the delivery ledger in this patch.

Max-attempt / backoff policy:

- Retries operate on the same `notification_events` row; no duplicate ledger rows are created.
- Default max attempts: `3`
- Default backoff schedule: first retry after `60s`, second retry after `300s`
- Once max attempts are exhausted, the row remains `failed` with `next_attempt_at = null`

Operational inspection / replay:

- Inspect backlog:

```sql
SELECT
  id,
  event_key,
  delivery_status,
  attempt_count,
  attempted_at,
  sent_at,
  failed_at,
  failure_reason,
  next_attempt_at,
  device_registration_id,
  game_id
FROM notification_events
WHERE delivery_status IN ('queued', 'failed')
ORDER BY COALESCE(next_attempt_at, created_at), created_at, id;
```

- Manually requeue a terminal failed row if needed:

```sql
UPDATE notification_events
SET
  delivery_status = 'queued',
  next_attempt_at = NULL,
  failure_reason = NULL
WHERE id = '...';
```

Optional manual sandbox smoke-test:

Required env:

- `DATABASE_URL`
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`
- `APNS_USE_SANDBOX=true`

The smoke test refuses to run when:

- `APNS_USE_SANDBOX` is not `true`
- any required APNs config is missing

Recommended operator sequence:

1. Fill the real APNs env vars in your local shell or a non-committed env file.
2. Place the APNs `.p8` key on local disk and make it readable by the operator account.
3. Seed exactly one test device + one queued notification row:

```bash
cd backend/collector
DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/kbo \
python seed_notification_smoke.py <sandbox-device-token>
```

4. Run preflight before the real send:

```bash
cd backend/collector
DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/kbo \
APNS_TEAM_ID=... \
APNS_KEY_ID=... \
APNS_BUNDLE_ID=... \
APNS_PRIVATE_KEY_PATH=/absolute/path/AuthKey_XXXX.p8 \
APNS_USE_SANDBOX=true \
python preflight_notification_delivery.py <notification_event_id>
```

One-off command:

```bash
cd backend/collector
DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/kbo \
APNS_TEAM_ID=... \
APNS_KEY_ID=... \
APNS_BUNDLE_ID=... \
APNS_PRIVATE_KEY_PATH=/absolute/path/AuthKey_XXXX.p8 \
APNS_USE_SANDBOX=true \
python smoke_notification_delivery.py <notification_event_id>
```

This path sends exactly one explicit `queued` `notification_events.id` and does not scan the broader backlog.

Seed helper behavior:

- creates or reuses one `device_registrations` row for the provided token
- creates or reuses one deterministic `notification_events` row for the smoke target
- resets that row to `delivery_status='queued'`
- does not bulk-generate rows

Equivalent manual seed SQL for one test device and one queued notification:

```sql
WITH seeded_team AS (
  INSERT INTO teams (code, name_ko, short_name, sort_order)
  VALUES
    ('LG', 'LG 트윈스', 'LG', 1),
    ('KT', 'KT 위즈', 'KT', 2)
  ON CONFLICT (code) DO UPDATE
  SET name_ko = EXCLUDED.name_ko,
      short_name = EXCLUDED.short_name,
      sort_order = EXCLUDED.sort_order
  RETURNING id, code
),
seeded_game AS (
  INSERT INTO games (
    provider,
    provider_game_id,
    game_date,
    scheduled_at,
    stadium,
    stadium_code,
    home_team_id,
    away_team_id,
    status,
    official_provider_game_id,
    provider_game_id_kind
  )
  SELECT
    'kbo',
    'manual-smoke-20260328',
    DATE '2026-03-28',
    TIMESTAMPTZ '2026-03-28 18:30:00+09',
    '잠실',
    'JS',
    (SELECT id FROM seeded_team WHERE code = 'LG'),
    (SELECT id FROM seeded_team WHERE code = 'KT'),
    'scheduled',
    'manual-smoke-20260328',
    'official'
  ON CONFLICT DO NOTHING
  RETURNING id
),
selected_game AS (
  SELECT id FROM seeded_game
  UNION ALL
  SELECT id FROM games WHERE provider_game_id = 'manual-smoke-20260328'
  LIMIT 1
),
seeded_device AS (
  INSERT INTO device_registrations (
    device_token,
    platform,
    app_version,
    favorite_team_id,
    notifications_enabled
  )
  SELECT
    '<sandbox-device-token>',
    'ios',
    'manual-smoke',
    (SELECT id FROM seeded_team WHERE code = 'LG'),
    TRUE
  ON CONFLICT (device_token) DO UPDATE
  SET notifications_enabled = TRUE,
      favorite_team_id = EXCLUDED.favorite_team_id
  RETURNING id
)
INSERT INTO notification_events (
  device_registration_id,
  game_id,
  event_type,
  event_key,
  title,
  body,
  payload_json,
  delivery_status
)
SELECT
  d.id,
  g.id,
  'postponed_confirmed',
  'manual-smoke:' || g.id::text || ':postponed_confirmed',
  '경기 우천 취소',
  '수동 sandbox smoke test 알림입니다.',
  jsonb_build_object('manual_smoke', true),
  'queued'
FROM seeded_device d
CROSS JOIN selected_game g
RETURNING id;
```

Run:

```bash
cd backend/collector
DATABASE_URL=postgresql://admin:adminkbo@127.0.0.1:55432/kbo \
APNS_TEAM_ID=... \
APNS_KEY_ID=... \
APNS_BUNDLE_ID=... \
APNS_PRIVATE_KEY_PATH=/absolute/path/AuthKey_XXXX.p8 \
APNS_USE_SANDBOX=true \
python smoke_notification_delivery.py <returned-notification-event-id>
```

Check eligible devices before send:

```sql
SELECT
  id,
  notifications_enabled,
  CASE WHEN NULLIF(BTRIM(device_token), '') IS NULL THEN 'blank' ELSE 'present' END AS token_state
FROM device_registrations
WHERE notifications_enabled = TRUE
ORDER BY created_at DESC;
```

Check queued notifications before send:

```sql
SELECT
  id,
  event_key,
  delivery_status,
  device_registration_id,
  game_id,
  created_at
FROM notification_events
WHERE delivery_status = 'queued'
ORDER BY created_at DESC, id DESC;
```

Expected logs:

- success:
  - `database_ready`
  - `manual_notification_smoke_test_finished` with `sent_rows=1`, `failed_rows=0`, `use_sandbox=true`
- failure:
  - `manual_notification_smoke_test_finished` with `failed_rows=1`
  - or an immediate APNs configuration error before send

Inspect the target row after the run:

```sql
SELECT
  id,
  delivery_status,
  attempt_count,
  attempted_at,
  sent_at,
  failed_at,
  failure_reason
FROM notification_events
WHERE id = '<notification_event_id>'::uuid;
```

Interpretation:

- success:
  - `delivery_status = 'sent'`
  - `sent_at` populated
- failure:
  - `delivery_status = 'failed'`
  - `failure_reason` populated
  - `next_attempt_at` may be populated for retryable transport failures

Common failure patterns:

- token/topic mismatch:
  - `failure_reason` like `BadDeviceToken` or `DeviceTokenNotForTopic`
  - terminal; device row may be disabled
- transient transport/APNs outage:
  - `failure_reason` like `apns_timeout`, `apns_transport_error`, `apns_http_500`
  - retryable; inspect `next_attempt_at`
- missing config:
  - command fails before send with `APNSConfigurationError`

Cleanup:

```sql
DELETE FROM notification_events WHERE event_key LIKE 'manual-smoke:%';
DELETE FROM device_registrations WHERE device_token = '<sandbox-device-token>';
DELETE FROM games WHERE provider_game_id = 'manual-smoke-20260328';
```

Preflight command behavior:

- checks required env vars
- checks `.p8` path exists and is readable
- checks `APNS_USE_SANDBOX=true`
- checks DB reachability
- checks at least one eligible device row exists
- checks at least one queued notification row exists
- if a `notification_event_id` is passed, also checks that exact row is still queued

This remains a manual operator check only. It is not run in CI, and real Apple sandbox/production delivery is still unverified unless explicitly performed by an operator.

What is still not implemented:

- Real Apple APNs infrastructure has still not been exercised in this repo.
- No dead-letter workflow exists beyond terminal `failed` rows.
- No authenticated user-facing notification inbox/read API is added here.

## Current public contract assumptions

The current DB schema is collector-oriented, so the read API maps a few fields explicitly:

- `gameId` currently maps to `games.id::text`
- `stadiumId` currently maps to `games.stadium_code`
- weather `condition` currently maps to `weather_snapshots.current_icon_name`
- `isDoubleHeader` currently returns `false` because no canonical column exists yet

These assumptions are documented in the repository/service layer so they remain visible until the schema evolves.

| Public field | Current backing column/source | Limitation |
| --- | --- | --- |
| `gameId` | `games.id::text` | UUID-backed identifier, not a domain game code |
| `stadiumId` | `games.stadium_code` | Uses collector stadium code, not a separate stadium dimension |
| `weather.condition` | `weather_snapshots.current_icon_name` | Icon label approximation, not a dedicated condition text column |
| `isDoubleHeader` | hard-coded `false` | No canonical doubleheader field exists yet |
| `score.home` / `score.away` | `games.home_score`, `games.away_score` | Pregame rows may still show `0` because canonical defaults are zero |
| `events[].eventType` | `game_schedule_events.event_type` | Only event types that current collector inputs can determine conservatively are emitted |
| `events[].reason` | `game_schedule_events.reason` | Optional and source-dependent; not every source provides a canonical reason |
