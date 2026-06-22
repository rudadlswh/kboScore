# Security Operations

## APNs Private Key Handling

Do not keep APNs provider private keys in the app repository, backend repository, or shared workspace root. Move `AuthKey_C93NV8FJT5.p8` to an operator-controlled secure location outside the repositories, then point backend configuration such as `APNS_PRIVATE_KEY_PATH` to that location.

Recommended local permission:

```sh
chmod 600 /secure/path/AuthKey_C93NV8FJT5.p8
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
