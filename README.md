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

Push uses the platform's native transport, matching how the platform sends:
**iOS → APNs directly** (no Firebase), **Android → FCM**.

- **iOS**: use the built-in `ApnsPushProvider` — see [IOS_SETUP.md](./IOS_SETUP.md)
  for the Xcode steps (capabilities, App Group, Notification Service Extension).
- **Android**: implement `PushProvider` with `firebase_messaging` (below).

Pick the provider per platform:

```dart
import 'dart:io' show Platform;
final push = Platform.isIOS ? ApnsPushProvider() : FcmPushProvider();
await EngageKaro.instance.initialize(config, push: push);
```

### Android provider (firebase_messaging)

Implement `PushProvider` with `firebase_messaging` and pass it to `initialize`:

```dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:engagekaro_flutter/engagekaro_flutter.dart';

class FcmPushProvider implements PushProvider {
  final _fm = FirebaseMessaging.instance;

  @override
  SubscriptionType get subscriptionType =>
      Platform.isIOS ? SubscriptionType.iosPush : SubscriptionType.androidPush;

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onNotificationOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async {
    final m = await _fm.getInitialMessage();
    return m?.data;
  }
}

// wire it up:
await EngageKaro.instance.initialize(config, push: FcmPushProvider());
await EngageKaro.instance.requestPushPermission();
```

## What maps to the backend

| SDK call | Endpoint |
|---|---|
| `login(id)` | `POST /api/sdk/users` |
| push/email/SMS register | `POST /api/sdk/users/:id/subscriptions` |
| `user.addTag(s)` | `PUT /api/sdk/users/:id/tags` |
| `trackEvent` | `POST /api/sdk/events` |

Auth uses the project **SDK key** as a bearer token. Use HTTPS in production.
