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
