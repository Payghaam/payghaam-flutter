# engagekaro_flutter

Flutter SDK for the EngageKaro engagement platform. Identify users, register
push/email/SMS subscriptions, set tags, and track events.

See [DESIGN.md](./DESIGN.md) for architecture and the native-push strategy.

## Install

```yaml
dependencies:
  engagekaro_flutter:
    path: ../sdks/flutter   # or a git/pub ref once published
```

## Quick start

```dart
import 'package:engagekaro_flutter/engagekaro_flutter.dart';

await EngageKaro.instance.initialize(EngageKaroConfig(
  appId: 'YOUR_PROJECT_ID',
  apiKey: 'ek_client_...',          // SDK-type key from the dashboard
  baseUrl: 'https://api.yourhost.com',
));

await EngageKaro.instance.login('your-backend-user-id');
await EngageKaro.instance.user.addTag('plan', 'pro');
await EngageKaro.instance.user.addEmail('user@example.com');
await EngageKaro.instance.trackEvent('purchase', {'sku': 'sku_123'});
```

## Enabling push

Push is native on **both** platforms from this one plugin — **iOS → APNs**
(no Firebase), **Android → FCM** (the plugin depends on the `firebase-messaging`
Android library directly). There's **no platform branch** and no `firebase_messaging`
in your app's pubspec.

`EngageKaroPushProvider` is the default, so simply:

```dart
final push = EngageKaroPushProvider();
await EngageKaro.instance.initialize(config, push: push); // or omit push — it's the default
await EngageKaro.instance.login('user-id');
await EngageKaro.instance.requestPushPermission();

// Enable terminated-state `delivered` receipts (iOS NSE + Android FCM service):
await push.shareConfig(
  appGroup: 'group.com.yourcompany.app.engagekaro', // iOS only; Android ignores it
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'user-id',
);
```

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
await EngageKaro.instance.login('user-id', identityHash: hash);
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
