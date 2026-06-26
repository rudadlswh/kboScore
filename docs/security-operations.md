# Security Operations

## APNs Private Key Handling

Do not keep APNs provider private keys in the app repository, backend repository, or shared workspace root. Keep APNs keys in an operator-controlled secure path outside every repository, then point backend configuration such as `APNS_PRIVATE_KEY_PATH` to that path.

Recommended local permission:

```sh
chmod 600 /secure/path/AuthKey_<key-id>.p8
```

Verify private keys are ignored:

```sh
git -C /Users/chogyeongmin/develop/kbo/kboScore check-ignore -v test.p8 test.pem test.key
git -C /Users/chogyeongmin/develop/kbo/kbo_back check-ignore -v test.p8 test.pem test.key
```

Check whether a key was ever committed:

```sh
git -C /Users/chogyeongmin/develop/kbo/kboScore log --all --name-only -- '*.p8' '*.pem' '*.key'
git -C /Users/chogyeongmin/develop/kbo/kbo_back log --all --name-only -- '*.p8' '*.pem' '*.key'
```

If an APNs private key appears in git history or may have been shared outside the secure operator location, revoke it in Apple Developer and create a new key before using production push notifications.

## Secret Configuration

Production secrets must be configured as Render environment variables, not committed files. This includes database URLs, database credentials, admin API keys, APNs team/key IDs, APNs private key paths, and push enablement flags.

Local development `.env` files must stay separate from examples. Keep real values only in ignored `.env` files, and keep `.env.example` files limited to key names with empty placeholder values.

If a secret may have been exposed:

1. Revoke or rotate it at the source system.
2. Update Render environment variables with the new value.
3. Redeploy the backend.
4. Search git history and GitHub remote history for the exposed filename or variable name.

## Supabase Public Read Boundary

The app reads Supabase through public projection views only. These views currently use `security_invoker=false`, so each view definition is the public security boundary and must not expose device tokens, live activity tokens, notification rows, crawl failures, raw archives, admin state, or Flyway internals.

Current public views and intended columns:

- `public_teams`: `id`, `team_code`, `name`, `short_name`
- `public_games`: `id`, `public_game_id`, `provider`, `provider_game_id`, `official_provider_game_id`, `game_date`, `scheduled_at`, `stadium`, `status`, `status_reason`, `home_team_id`, `away_team_id`, `home_score`, `away_score`, `inning_state`, `is_cancelled`, `is_postponed`, `source_updated_at`, `updated_at`, `final_confirmed_at`, `live_last_checked_at`, `away_starting_pitcher_name`, `home_starting_pitcher_name`
- `public_game_events`: `id`, `game_id`, `provider_event_id`, `sequence_number`, `inning`, `inning_half`, `event_type`, `event_text`
- `public_latest_game_snapshots`: game state and player display fields only; no raw hashes or raw payloads
- `public_game_batter_records`, `public_game_pitcher_records`: boxscore display/stat columns only
- `team_rank_2026`: ranking display/stat columns only

Run the SQL in `kbo_back/docs/supabase-security-check.sql` before production releases and after every migration that changes grants, tables, or views.

TODO: evaluate switching public projection views to `security_invoker=true` with explicit RLS policies once the app-facing RLS model is fully covered by tests.

## Release Backend Validation Negative Test

`scripts/validate_release_backend_config.sh` must fail Release builds when Live Activity registration is empty, HTTP, localhost, or outside the configured production backend base URL.

Example failure checks:

```sh
CONFIGURATION=Release \
KBO_BACKEND_BASE_URL=https://kboscore-back.onrender.com \
KBO_NOTIFICATION_REGISTRATION_URL=https://kboscore-back.onrender.com/devices/register \
KBO_LIVE_ACTIVITY_REGISTRATION_URL=http://localhost:8088/devices/live-activities/register \
KBO_APNS_ENVIRONMENT=production \
scripts/validate_release_backend_config.sh

CONFIGURATION=Release \
KBO_BACKEND_BASE_URL=https://kboscore-back.onrender.com \
KBO_NOTIFICATION_REGISTRATION_URL=https://kboscore-back.onrender.com/devices/register \
KBO_LIVE_ACTIVITY_REGISTRATION_URL= \
KBO_APNS_ENVIRONMENT=production \
scripts/validate_release_backend_config.sh
```

Both commands should exit non-zero.
