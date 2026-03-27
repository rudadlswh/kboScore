#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
COLLECTOR_DIR="$BACKEND_DIR/collector"
COMPOSE_FILE="$BACKEND_DIR/docker-compose.yml"
ENV_FILE="$BACKEND_DIR/.env"
ENV_EXAMPLE_FILE="$BACKEND_DIR/.env.example"
VENV_DIR="${VENV_DIR:-$COLLECTOR_DIR/.venv-test}"
ENV_SOURCE=""

if [[ -n "${PYTHON_BIN:-}" ]]; then
  SELECTED_PYTHON_BIN="$PYTHON_BIN"
else
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      SELECTED_PYTHON_BIN="$candidate"
      break
    fi
  done
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to start the local Postgres test dependency." >&2
  exit 1
fi

if [[ -z "${SELECTED_PYTHON_BIN:-}" ]] || ! command -v "$SELECTED_PYTHON_BIN" >/dev/null 2>&1; then
  echo "A supported Python interpreter is required (python3.10+)." >&2
  exit 1
fi

PYTHON_VERSION_CHECK="$("$SELECTED_PYTHON_BIN" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"

case "$PYTHON_VERSION_CHECK" in
  3.10|3.11|3.12|3.13)
    ;;
  *)
    echo "Unsupported Python version: $PYTHON_VERSION_CHECK. Use PYTHON_BIN=python3.11 or newer." >&2
    exit 1
    ;;
esac

if [[ -x "$VENV_DIR/bin/python" ]]; then
  EXISTING_VENV_VERSION="$("$VENV_DIR/bin/python" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
  if [[ "$EXISTING_VENV_VERSION" != "$PYTHON_VERSION_CHECK" ]]; then
    rm -rf "$VENV_DIR"
  fi
fi

if [[ -f "$ENV_FILE" ]]; then
  ENV_SOURCE="$ENV_FILE"
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
elif [[ -f "$ENV_EXAMPLE_FILE" ]]; then
  ENV_SOURCE="$ENV_EXAMPLE_FILE"
  # shellcheck disable=SC1090
  set -a && source "$ENV_EXAMPLE_FILE" && set +a
else
  echo "backend/.env or backend/.env.example is required." >&2
  exit 1
fi

POSTGRES_DB="${POSTGRES_DB:-kbo}"
POSTGRES_USER="${POSTGRES_USER:-admin}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-adminkbo}"
LOCAL_TEST_POSTGRES_PORT="${LOCAL_TEST_POSTGRES_PORT:-55432}"

export TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${LOCAL_TEST_POSTGRES_PORT}/kbo_test}"
export TEST_ADMIN_DATABASE_URL="${TEST_ADMIN_DATABASE_URL:-postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${LOCAL_TEST_POSTGRES_PORT}/postgres}"

docker compose --env-file "$ENV_SOURCE" -f "$COMPOSE_FILE" up -d postgres >/dev/null

for _ in $(seq 1 30); do
  if docker compose --env-file "$ENV_SOURCE" -f "$COMPOSE_FILE" exec -T postgres \
    pg_isready -U "$POSTGRES_USER" -d postgres >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker compose --env-file "$ENV_SOURCE" -f "$COMPOSE_FILE" exec -T postgres \
  pg_isready -U "$POSTGRES_USER" -d postgres >/dev/null 2>&1; then
  echo "postgres did not become ready in time." >&2
  exit 1
fi

if [[ ! -d "$VENV_DIR" ]]; then
  "$SELECTED_PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV_DIR/bin/python" -m pip install -r "$COLLECTOR_DIR/requirements.txt" -r "$COLLECTOR_DIR/requirements-test.txt" >/dev/null

cd "$COLLECTOR_DIR"
"$VENV_DIR/bin/python" -m pytest tests/integration "$@"
