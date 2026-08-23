# payghaam_flutter

Flutter SDK for the Payghaam engagement platform. Identify users, register
push/email/SMS subscriptions, set tags, and track events.

See [DESIGN.md](./DESIGN.md) for architecture and the native-push strategy.

## Prerequisites

- Flutter ≥ 3.10.0, Dart SDK ≥ 3.0.0 (`>=3.0.0 <4.0.0`)
- iOS 15.0+ deployment target
- Android `minSdk` 21+
- A Payghaam project + SDK-type API key (dashboard → Project → API keys)

## Install

```yaml
dependencies:
  payghaam_flutter: ^0.2.0
```

## Automate native setup

From your **app** root (not this package), after `flutter pub add payghaam_flutter`:

```bash
dart run payghaam_flutter:install
```

That is the `flutterfire configure` equivalent for this plugin. It is idempotent
(`--dry-run` prints the plan without writing). Flags: `--android`, `--ios`,
`--app-group=group.your.bundle.payghaam`.

| Platform | What the CLI writes | Still manual |
|---|---|---|
| **Android** | Google services Gradle plugin (`settings.gradle(.kts)` + `app/build.gradle(.kts)`), minSdk ≥ 21 / JVM 17 if those are hardcoded too low | `android/app/google-services.json` from Firebase; FCM service-account JSON in the Payghaam dashboard; optional deep-link intent-filter |
| **iOS** | Push + App Group entitlements, `PayghaamAppGroup`, Background Modes (`remote-notification`), `PayghaamNSE` target + `NotificationService.swift` from this package, CocoaPods `target 'PayghaamNSE'` **or** SPM `Payghaam` on that target | APNs `.p8` / Key ID / Team ID / Bundle ID in the Payghaam dashboard; enable the App Group on the App ID if Xcode signing asks |

Then initialize in Dart as in [Quick start](#quick-start) and call
`shareConfig` with the same App Group id the CLI printed (convention
`group.<bundle_id>.payghaam`).

Prefer to click through Xcode yourself? See [IOS_SETUP.md](./IOS_SETUP.md) and
[ANDROID_SETUP.md](./ANDROID_SETUP.md) — those steps remain as a fallback.

## Quick start

```dart
import 'package:payghaam_flutter/payghaam_flutter.dart';

void main() async {
  await Payghaam.instance.initialize(PayghaamConfig(
    appId: 'YOUR_PROJECT_ID',
    apiKey: 'ek_client_...',          // SDK-type key from the dashboard
    baseUrl: 'https://api.yourhost.com',
  ));

  await Payghaam.instance.login('your-backend-user-id');
  await Payghaam.instance.user.addTag('plan', 'pro');
  await Payghaam.instance.user.addEmail('user@example.com');
  await Payghaam.instance.trackEvent('purchase', {'sku': 'sku_123'});
}
```

## Enabling push

Push is native on **both** platforms from this one plugin — **iOS → APNs**
(no Firebase), **Android → FCM**. There's **no platform branch** and no
`firebase_messaging` in your app's pubspec.

`PayghaamPushProvider` is the default, so simply:

```dart
final push = PayghaamPushProvider();
await Payghaam.instance.initialize(config, push: push); // or omit push — it's the default
await Payghaam.instance.login('user-id');
await Payghaam.instance.requestPushPermission(); // don't call this at launch — see below

// Enable terminated-state `delivered` receipts (iOS NSE + Android FCM service):
await push.shareConfig(
  appGroup: 'group.com.yourcompany.app.payghaam', // iOS only; Android ignores it
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'user-id',
);
```

Defer `requestPushPermission()` until the user has context for why you're asking — a prompt fired at cold launch gets reflexively denied, and a denial is hard to undo. Call it after onboarding, or right before a feature that needs push (e.g. `await Payghaam.instance.requestPushPermission();` right before enabling order-status alerts).

## Sessions

After `login()`, the SDK reports `session_start` on cold start and when the app
returns to the foreground after at least 30 seconds in the background. That is
what “last session” / inactive-N-days segments use. `login()` / identify by
itself is not a session, and neither is opening a push.

## Handling taps and deep links

A campaign's **Deep link URL** arrives as `ek_url`, and anything you pass as `data`
on `POST /api/notifications` arrives alongside it:

```dart
Payghaam.instance.onNotificationOpened.listen((payload) {
  // payload['ek_url']   → 'myapp://offers/summer'
  // payload['targetId'] → your own data key
  final target = payload['targetId'];
  if (target is String) navigatorKey.currentState?.pushNamed('/offers/$target');
});
```

With **no** subscriber, the SDK opens `ek_url` itself (`ACTION_VIEW` on Android,
`openURL` on iOS). Subscribing suppresses that, so routing — including the deep link —
is yours. Subscribe right after `initialize()`; a tap that cold-launched the app waits
a short grace period for you before the fallback takes over.

> **Subscribe via `Payghaam.instance.onNotificationOpened`, not the provider's
> stream.** Both deliver the same payload, but the SDK's own stream is the public
> API, and subscribing to it is what tells the SDK you're handling routing.

> **The scheme must be registered with the OS or nothing opens.** A custom scheme
> like `myapp://` is claimed by no app until you declare it — an `<intent-filter>`
> on Android ([setup](./ANDROID_SETUP.md#4-register-your-deep-link-scheme-required-for-the-campaign-deep-link-url))
> and a URL Type on iOS ([setup](./IOS_SETUP.md)). Until then the tap opens the app
> and your listener still fires, but the automatic fallback has nowhere to send it.

Reserved payload keys: `ek_message_id`, `ek_url`, `ek_image`, `ek_sound`, `title`, `body`.

## Live Activities (iOS)

Payghaam drives Live Activities from your **server**. Appearance is your
SwiftUI Widget Extension; this plugin reuses **payghaam-ios** for token
registration — it does not rebuild ActivityKit in Dart.

### Host AppDelegate (required)

After plugin registration, observe your attributes type (before `login()`):

```swift
import Payghaam

GeneratedPluginRegistrant.register(with: self)
if #available(iOS 16.1, *) {
  PayghaamLiveActivities.observe(DeliveryAttributes.self)
}
```

The plugin implements `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
and forwards to `Payghaam.shared.handleRemoteNotification(...)` so push-to-start
/ suspended updates still mint and POST update tokens.

Requires Payghaam iOS **≥ 0.1.4** (CocoaPods / SPM).

### Dart

```dart
await PayghaamLiveActivities.refresh(); // → PayghaamLiveActivities.refreshAll()

PayghaamLiveActivities.onUpdateTokenRegistered.listen((e) {
  // e['activityId'], e['ok'], optional e['error']
});
```

**Local start from Flutter** needs a typed `ActivityAttributes` in Swift. The
example app implements `payghaam/liveActivitiesLocal` with `DeliveryAttributes`
(`startActivity` / `updateActivity` / `endActivity`). Copy that pattern into
your app — do not try to encode arbitrary attributes from Dart.

### Server REST (project REST key, not the SDK key)

```bash
POST   /api/live-activities
PATCH  /api/live-activities/order-4821
DELETE /api/live-activities/order-4821
```

After **push-to-start**, the user must tap **Allow** on the lock-screen activity
before ActivityKit mints the update token. Local starts do not require that step.

### Widget Extension

Add a Widget Extension in Xcode (Include Live Activity), share your attributes
struct with Runner, set `NSSupportsLiveActivities` = `YES`, and enable Push on
both targets. See [IOS_SETUP.md](./IOS_SETUP.md#live-activities) and the
example under `example/ios/LiveActivity/`.

Platform setup:

- **iOS** — [IOS_SETUP.md](./IOS_SETUP.md): capabilities, App Group, Notification
  Service Extension, Live Activities.
- **Android** — [ANDROID_SETUP.md](./ANDROID_SETUP.md): add a Firebase project +
  `google-services.json` (no `firebase_messaging` plugin needed).
- **Custom sounds** — [CUSTOM_SOUND.md](./CUSTOM_SOUND.md): bundle a sound file
  and map the dashboard's *Custom sound* name to it on each platform.

## Identity Verification

If a project enables Identity Verification (dashboard → project → Security),
SDK calls referencing an external id must include an HMAC-SHA256 of that id,
computed **on your server** with the project secret:

```dart
// hash = HMAC_SHA256(externalId, projectSecret) — computed by YOUR backend
await Payghaam.instance.login('user-id', identityHash: hash);
```

Never ship the secret in the app.

## What maps to the backend

| SDK call | Endpoint |
|---|---|
| `login(id)` | `POST /api/sdk/users` |
| push/email/SMS register | `POST /api/sdk/users/:id/subscriptions` |
| `user.addTag(s)` | `PUT /api/sdk/users/:id/tags` |
| `trackEvent` | `POST /api/sdk/events` |

Auth uses the project **SDK key** as a bearer token. Use HTTPS in production.

## Verify your integration

1. Run the app on a physical device (push needs real APNs/FCM, not a simulator/emulator).
2. Confirm the SDK initialized — pass `debug: true` in `PayghaamConfig` for verbose console logging.
3. Check the dashboard (Project → Subscribers) for a new subscriber after `login()`.
4. Send a test push from the dashboard (Project → Campaigns → test send) targeting that subscriber.
5. Confirm it's delivered, and that tapping it fires `onNotificationOpened` and/or opens the deep link.

## Architecture

This plugin is a thin wrapper over the canonical native SDKs (`sdks/ios`,
`sdks/android`) rather than its own implementation — see
`DESIGN.md` at the repo root for the full design.

- **iOS/Android**: `initialize`/`login`/`trackEvent`/`user.addTag(s)`/push
  registration/receipt reporting all delegate to the native SDK (via a
  CocoaPods/SPM dependency on iOS, a Gradle composite build on Android), which
  owns the HTTP client and offline queue. Dart only owns tap dispatch,
  deep-link fallback, and foreground/session timing — deliberately, so those
  don't get double-handled by both the native SDK's own machinery and the
  plugin's.
- **Web/desktop**: there's no native SDK to delegate to on these platforms
  (push was never supported there either), so Dart falls back to its own
  `package:http`-based client automatically when the native plugin isn't
  present. That's the one place this SDK still makes its own HTTP calls.

## Docs follow-up

PRs that change native setup or the public Dart API get a bot comment pointing at the matching pages in [payghaam-mono](https://github.com/Payghaam/payghaam-mono) (`/docs/sdk/flutter`). Mono also clones this public repo weekly and can open the docs PR there. See [`.github/DOCS-FOLLOW-UP.md`](.github/DOCS-FOLLOW-UP.md).
