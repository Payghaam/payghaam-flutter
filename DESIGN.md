# EngageKaro Flutter SDK — Design

Derived from a review of the OneSignal Flutter SDK setup guide. Goal: give a
Flutter app a small, OneSignal-shaped API to identify users, manage
subscriptions, set tags, and track events against the EngageKaro platform.

## What the OneSignal SDK actually does (and what we need)

The OneSignal SDK has two separable layers:

1. **Native push plumbing** — obtains the FCM token (Android) and APNs token
   (iOS), shows notifications, runs the iOS Notification Service Extension (rich
   media + confirmed delivery), prompts for permission, and surfaces
   click/foreground events.
2. **Platform communication** — REST calls to the backend to `login` (set
   External ID), register subscriptions (push/email/SMS), `addTag(s)`, track
   events/outcomes, and gate on consent.

**Layer 2 is the SDK's real job, and it maps 1:1 onto endpoints we already have.**
Layer 1 is the platform-specific heavy lifting.

### Endpoint mapping (already built on the server)

| SDK action | EngageKaro endpoint | Auth |
|---|---|---|
| `login(externalId)` / identify | `POST /api/sdk/users` | SDK key |
| register push token / email / SMS | `POST /api/sdk/users/:externalId/subscriptions` | SDK key |
| `addTag(s)` / `removeTag` | `PUT /api/sdk/users/:externalId/tags` | SDK key |
| `trackEvent(name, props)` | `POST /api/sdk/events` | SDK key |
| consent withdrawal / unsubscribe | `POST /api/sdk/opt-out` | SDK key |

Auth is the project's **SDK-type API key** (created in the dashboard → project →
API Keys), sent as `Authorization: Bearer <key>`.

## Public API (OneSignal-shaped)

```dart
await EngageKaro.instance.initialize(EngageKaroConfig(
  appId: 'project_id',          // EngageKaro project id
  apiKey: 'ek_client_...',      // SDK-type key
  baseUrl: 'https://api.yourhost.com',
  requireConsent: false,
));

await EngageKaro.instance.login('your-app-user-id');     // External ID
await EngageKaro.instance.user.addTag('plan', 'pro');
await EngageKaro.instance.user.addTags({'level': '6'});
await EngageKaro.instance.user.addEmail('a@b.com');
await EngageKaro.instance.user.addSms('+1555...');
await EngageKaro.instance.trackEvent('purchase', {'sku': 'x'});
await EngageKaro.instance.logout();

// consent gating
EngageKaro.instance.setConsentGiven(true);
```

## The native-push fork (the one real decision)

Layer 1 has two viable strategies:

- **A — Lean on `firebase_messaging` (recommended to start).** Use FlutterFire's
  `firebase_messaging` for token acquisition, permission, and notification
  display on **both** platforms (FCM can deliver to APNs once the host app has
  the standard iOS push setup). Our SDK stays Dart-only: it reads the token from
  `firebase_messaging` and registers it via the REST client; a notification tap
  calls `trackEvent('push_opened', …)`. Fast to ship, minimal native code, but
  iOS rich notifications / confirmed-delivery (NSE) come later.

- **B — Full native plugin (like OneSignal).** Ship a Flutter plugin with native
  Kotlin (FirebaseMessagingService) and Swift (APNs registration + NSE) code.
  Full feature parity (rich push, confirmed receipt, badges) but weeks of
  platform work and a Mac/Xcode toolchain to build and test.

This SDK core is written **provider-agnostic**: it exposes a `PushProvider`
interface and a `registerPushToken(token, platform)` method, so either strategy
plugs in without changing the comms layer.

## Package layout

```
sdks/flutter/
  pubspec.yaml
  lib/
    engagekaro_flutter.dart      # barrel export
    src/
      config.dart                # EngageKaroConfig, SubscriptionType
      api_client.dart            # REST client over /api/sdk/*
      engagekaro.dart            # facade: initialize/login/logout/consent/track
      user_manager.dart          # tags, email, sms
      notifications.dart         # PushProvider interface + Notifications facade
      storage.dart               # persist externalId + anonymous device id
```

## Phased plan

1. **Comms core (this scaffold).** Dart-only client + public API. Buildable and
   unit-testable today, no native toolchain required.
2. **Push provider.** Add a `firebase_messaging`-backed `PushProvider`
   (strategy A) wired to `registerPushToken`, plus a click→`push_opened` hook.
3. **iOS NSE + confirmed delivery** (only if strategy B / parity is required).
4. **Examples + pub.dev publishing + identity verification (HMAC) hardening.**

## Security notes

- The SDK uses the **SDK-type** key (client-scoped), never the REST key.
- Add **Identity Verification** later: server issues an HMAC of the External ID
  so a client can't impersonate another user (OneSignal does this via
  `externalId` + auth hash). Backend needs a per-project secret + a verify step.
- All calls over HTTPS; never log keys or tokens.
