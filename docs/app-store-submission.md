# App Store Submission Draft

## Metadata

- App name: kboScore
- Subtitle: KBO live scores and schedule
- Category: Sports
- Keywords: KBO, baseball, live score, schedule, standings, box score, Korea baseball, push notification
- Support URL: TBD
- Privacy policy URL: TBD

## Description Draft

kboScore keeps Korean baseball fans close to the current KBO season.

Follow today's games, schedules, standings, line scores, box scores, favorite-team context, notifications, widgets, and Live Activities in one focused app. Select a favorite team to make the home screen, schedule, alerts, and Live Activity controls reflect the games you care about most.

Key features:

- KBO game schedule and daily results
- Live game state, score, inning, count, runners, and current players
- Favorite-team focused home and schedule views
- Standings and team records
- Box score detail for completed and live games when available
- Push notifications for selected game events
- Live Activities and widgets for favorite-team games

## Review Notes Draft

The app is a read-only KBO score and schedule viewer with optional push notifications and Live Activities.

- No account login is required.
- Favorite-team selection is stored locally and used to personalize schedule, home, widget, notification, and Live Activity behavior.
- Push notification registration sends APNs tokens, installation ID, favorite team, notification preferences, and APNs environment to the app backend only when notification registration is available.
- Backend endpoints used by Release builds must be configured with HTTPS production URLs before archive.

## App Privacy Nutrition Label Draft

Use Apple App Store Connect's privacy questionnaire and verify against the final backend/runtime behavior before submission. Apple states that privacy details must include the app and third-party partners' practices, and identify whether collected data is linked to the user or used for tracking.

Recommended current answers from code inspection:

- Tracking: No
- Data used to track user: None
- Data linked to user:
  - Identifiers: Device ID or installation identifier, used for app functionality, push notifications, and Live Activity token routing.
  - User Content or Other Data: Favorite team and notification preferences, used for app functionality.
- Data not linked to user:
  - Diagnostics: None, unless crash/analytics tooling is added before submission.
  - Usage data: None, unless analytics tooling is added before submission.

Privacy manifest evidence:

- `NSPrivacyTracking=false`
- Required reason API: UserDefaults, reason `CA92.1`

## Screenshots

Apple requires 1 to 10 screenshots in JPEG/JPG/PNG for each required device size. Capture production-looking screens after Release backend URL is configured:

- Home with favorite-team game state
- Schedule calendar/month view
- Game detail with box score
- Standings
- Notifications/settings or Live Activity/widget proof

Official references:

- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Screenshot Specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

## Remaining Before Submission

- Set `KBO_PRODUCTION_BACKEND_BASE_URL` in `Release.xcconfig`.
- Set `KBO_APPSTORE_APP_PROVISIONING_PROFILE_SPECIFIER` to an App Store profile with App Groups and Push Notifications.
- Set `KBO_APPSTORE_EXTENSION_PROVISIONING_PROFILE_SPECIFIER` to an App Store profile with App Groups.
- Install an Apple Distribution signing identity and the two App Store provisioning profiles on the archive machine.
- Run `scripts/app_store_release_preflight.sh` before archiving.
- Fill Support URL.
- Fill Privacy Policy URL.
- Confirm final privacy label after production backend and third-party SDK review.
- Capture screenshots from a Release or TestFlight-equivalent build.
- Archive and upload through Organizer.
- Export `.ipa` and verify `get-task-allow=false`.
