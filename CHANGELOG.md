## Unreleased

* Live Activities (iOS): plugin forwards push-wake to payghaam-ios
  (`handleRemoteNotification` → token refresh); Dart
  `PayghaamLiveActivities.refresh()` / token event streams; example
  AppDelegate `observe(DeliveryAttributes)` + local start/update/end
  method channel. CocoaPods/SPM require Payghaam iOS `>= 0.1.4`.
* Sessions: send `session_start` on cold start and when the app returns to the
  foreground after ≥30s in the background (OneSignal-style). Identify without
  that ping no longer counts as a session.

## 0.2.0

* Add `dart run payghaam_flutter:install`, an idempotent CLI that wires native
  push setup into the host Flutter app (`--android`, `--ios`, `--dry-run`,
  `--app-group=`).
* Android: applies the Google services Gradle plugin in `settings.gradle(.kts)`
  and `app/build.gradle(.kts)`, and raises minSdk / JVM target when hardcoded
  too low.
* iOS: adds Push + App Group entitlements, Background Modes, and a `PayghaamNSE`
  Notification Service Extension with `NotificationService.swift` from this
  package.
* Still manual after the CLI: place `android/app/google-services.json` from
  Firebase; add FCM / APNs credentials in the Payghaam dashboard; call
  `shareConfig` from Dart (App Group id on iOS).

## 0.1.2

* Fix: an API key/base URL change (e.g. rotating a key) wasn't picked up by
  the native iOS/Android bridge until the app process was fully killed and
  relaunched — a Flutter hot restart kept the old key bound natively,
  causing "Invalid API key" 401s. `initialize()`/`login()` now await the
  native sync instead of firing it unawaited, and the native SDKs rebind
  their client whenever the key/base URL actually changes.
* Pin Android native SDK to `com.payghaam:payghaam:0.1.7` (includes the
  hot-restart rebind fix already published on Maven Central).

## 0.1.0

* Initial release of the Payghaam Flutter SDK.
* User identification, tags, email/SMS subscriptions, and event tracking.
* Native push on iOS (APNs) and Android (FCM) via [PayghaamPushProvider].
* Pluggable [PushProvider] interface and consent gating.
