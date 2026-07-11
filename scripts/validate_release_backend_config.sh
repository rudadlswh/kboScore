#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

fail() {
    echo "error: $1" >&2
    exit 1
}

require_https_url() {
    name="$1"
    value="$2"

    [ -n "$value" ] || fail "$name is required for Release builds."

    if printf '%s' "$value" | grep -F '$(' >/dev/null 2>&1; then
        fail "$name is unresolved: $value"
    fi

    case "$value" in
        https://*) ;;
        *) fail "$name must use https:// for Release builds: $value" ;;
    esac

    case "$value" in
        *://localhost*|*://127.0.0.1*|*://[::1]*)
            fail "$name must not point to localhost for Release builds: $value"
            ;;
    esac
}

require_https_url "KBO_BACKEND_BASE_URL" "${KBO_BACKEND_BASE_URL:-}"
require_https_url "KBO_NOTIFICATION_REGISTRATION_URL" "${KBO_NOTIFICATION_REGISTRATION_URL:-}"
require_https_url "KBO_LIVE_ACTIVITY_REGISTRATION_URL" "${KBO_LIVE_ACTIVITY_REGISTRATION_URL:-}"

[ "${KBO_APNS_ENVIRONMENT:-}" = "production" ] || fail "KBO_APNS_ENVIRONMENT must be production for Release builds."

case "${KBO_NOTIFICATION_REGISTRATION_URL:-}" in
    */devices/register) ;;
    *) fail "KBO_NOTIFICATION_REGISTRATION_URL must end with /devices/register." ;;
esac

case "${KBO_LIVE_ACTIVITY_REGISTRATION_URL:-}" in
    */devices/live-activities/register) ;;
    *) fail "KBO_LIVE_ACTIVITY_REGISTRATION_URL must end with /devices/live-activities/register." ;;
esac

case "${KBO_NOTIFICATION_REGISTRATION_URL:-}" in
    "${KBO_BACKEND_BASE_URL%/}"/*) ;;
    *) fail "KBO_NOTIFICATION_REGISTRATION_URL must use the configured production backend base URL." ;;
esac

case "${KBO_LIVE_ACTIVITY_REGISTRATION_URL:-}" in
    "${KBO_BACKEND_BASE_URL%/}"/*) ;;
    *) fail "KBO_LIVE_ACTIVITY_REGISTRATION_URL must use the configured production backend base URL." ;;
esac
