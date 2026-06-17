#!/bin/sh
set -eu

PROJECT="${PROJECT:-kboScore.xcodeproj}"
SCHEME="${SCHEME:-kboScore}"
CONFIGURATION="${CONFIGURATION:-Release}"
SDK="${SDK:-iphoneos}"
BACKEND_BASE_URL="${KBO_PRODUCTION_BACKEND_BASE_URL:-}"
APP_PROFILE="${KBO_APPSTORE_APP_PROVISIONING_PROFILE_SPECIFIER:-}"
EXTENSION_PROFILE="${KBO_APPSTORE_EXTENSION_PROVISIONING_PROFILE_SPECIFIER:-}"

fail() {
    echo "error: $1" >&2
    exit 1
}

warn() {
    echo "warning: $1" >&2
}

require_non_empty() {
    name="$1"
    value="$2"
    [ -n "$value" ] || fail "$name is required."
}

require_https_url() {
    name="$1"
    value="$2"
    require_non_empty "$name" "$value"
    case "$value" in
        https://*) ;;
        *) fail "$name must use https://: $value" ;;
    esac
    case "$value" in
        *://localhost*|*://127.0.0.1*|*://[::1]*)
            fail "$name must not point to localhost: $value"
            ;;
    esac
}

cd "$(dirname "$0")/.."

require_https_url "KBO_PRODUCTION_BACKEND_BASE_URL" "$BACKEND_BASE_URL"
require_non_empty "KBO_APPSTORE_APP_PROVISIONING_PROFILE_SPECIFIER" "$APP_PROFILE"
require_non_empty "KBO_APPSTORE_EXTENSION_PROVISIONING_PROFILE_SPECIFIER" "$EXTENSION_PROFILE"

if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    fail "No Apple Distribution signing identity is installed in the keychain."
fi

profile_count=$(find "$HOME/Library/MobileDevice/Provisioning Profiles" -name '*.mobileprovision' -maxdepth 1 -print 2>/dev/null | wc -l | tr -d ' ')
if [ "$profile_count" = "0" ]; then
    fail "No provisioning profiles are installed under ~/Library/MobileDevice/Provisioning Profiles."
fi

settings=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk "$SDK" \
    "KBO_PRODUCTION_BACKEND_BASE_URL=$BACKEND_BASE_URL" \
    "KBO_APPSTORE_APP_PROVISIONING_PROFILE_SPECIFIER=$APP_PROFILE" \
    "KBO_APPSTORE_EXTENSION_PROVISIONING_PROFILE_SPECIFIER=$EXTENSION_PROFILE" \
    -showBuildSettings)

printf '%s\n' "$settings" | grep -E "TARGET_NAME|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|KBO_BACKEND_BASE_URL|KBO_NOTIFICATION_REGISTRATION_URL|APS_ENVIRONMENT|PRODUCT_BUNDLE_IDENTIFIER"

printf '%s\n' "$settings" | grep -q "CODE_SIGN_STYLE = Manual" || warn "Manual signing was not found in build settings output."
printf '%s\n' "$settings" | grep -q "CODE_SIGN_IDENTITY = Apple Distribution" || fail "Release build is not using Apple Distribution."
printf '%s\n' "$settings" | grep -q "KBO_BACKEND_BASE_URL = https://" || fail "Release backend URL did not resolve to HTTPS."
printf '%s\n' "$settings" | grep -q "KBO_NOTIFICATION_REGISTRATION_URL = .*/devices/register" || fail "Release registration URL did not resolve to /devices/register."
printf '%s\n' "$settings" | grep -q "APS_ENVIRONMENT = production" || fail "Release APS environment is not production."

echo "App Store Release preflight passed."
