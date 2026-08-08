# payghaam_flutter

Flutter SDK for the Payghaam engagement platform. Identify users, register
push/email/SMS subscriptions, set tags, and track events.

See [DESIGN.md](./DESIGN.md) for architecture and the native-push strategy.

## Install

```yaml
dependencies:
  payghaam_flutter:
    path: ../sdks/flutter   # or a git/pub ref once published
```

## Quick start

```dart
import 'package:payghaam_flutter/payghaam_flutter.dart';

await Payghaam.instance.initialize(PayghaamConfig(
  appId: 'YOUR_PROJECT_ID',
  apiKey: 'ek_client_...',          // SDK-type key from the dashboard
  baseUrl: 'https://api.yourhost.com',
));

await Payghaam.instance.login('your-backend-user-id');
await Payghaam.instance.user.addTag('plan', 'pro');
await Payghaam.instance.user.addEmail('user@example.com');
await Payghaam.instance.trackEvent('purchase', {'sku': 'sku_123'});
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
await Payghaam.instance.requestPushPermission();

// Enable terminated-state `delivered` receipts (iOS NSE + Android FCM service):
await push.shareConfig(
  appGroup: 'group.com.yourcompany.app.payghaam', // iOS only; Android ignores it
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'user-id',
);
```

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

Platform setup:

- **iOS** — [IOS_SETUP.md](./IOS_SETUP.md): capabilities, App Group, Notification
  Service Extension.
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

## Architecture

This plugin is a thin wrapper over the canonical native SDKs (`sdks/ios`,
`sdks/android`) rather than its own implementation — see
`sdk-native-wrapper-design.md` at the repo root for the full design.

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
