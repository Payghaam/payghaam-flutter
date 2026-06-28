# iOS setup (direct APNs, no Firebase)

The EngageKaro Flutter SDK ships native iOS code that registers for APNs, gets
the device token, and handles notification taps/foreground. A Notification
Service Extension (NSE) adds terminated-state **confirmed delivery** and rich
images. Android push is handled separately via `firebase_messaging` + a
`FcmPushProvider` — these steps are iOS only.

## 1. App capabilities (main app target)

In Xcode → your app target → **Signing & Capabilities**, add:

- **Push Notifications**
- **Background Modes** → enable **Remote notifications**
- **App Groups** → add a group id, e.g. `group.com.yourcompany.app.engagekaro`

## 2. Tell the app + extension the App Group

Add this key to the **app target's** `Info.plist` (and the NSE's later):

```xml
<key>EngageKaroAppGroup</key>
<string>group.com.yourcompany.app.engagekaro</string>
```

## 3. Use the iOS provider in Dart

```dart
import 'dart:io' show Platform;
import 'package:engagekaro_flutter/engagekaro_flutter.dart';

final config = EngageKaroConfig(
  appId: 'YOUR_PROJECT_ID',
  apiKey: 'ek_client_...',
  baseUrl: 'https://api.yourhost.com',
);

final apns = ApnsPushProvider();
await EngageKaro.instance.initialize(config, push: apns);
await EngageKaro.instance.login('your-user-id');
await EngageKaro.instance.requestPushPermission();

// Share config with the NSE so it can report delivery while terminated.
await apns.shareConfigForExtension(
  appGroup: 'group.com.yourcompany.app.engagekaro',
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'your-user-id',
);
```

> On Android, swap `ApnsPushProvider()` for your `FcmPushProvider` (see README)
> guarded by `Platform.isIOS`.

## 4. Add the Notification Service Extension

1. Xcode → **File ▸ New ▸ Target… ▸ Notification Service Extension**. Name it
   e.g. `EngageKaroNSE`. Don't activate the scheme.
2. Replace the generated `NotificationService.swift` with
   [`ios_extension/NotificationService.swift`](./ios_extension/NotificationService.swift).
3. NSE target → **Signing & Capabilities** → add **App Groups** → the **same**
   group id as the app.
4. NSE target → `Info.plist` → add the same `EngageKaroAppGroup` key/value.
5. Set the NSE **Minimum Deployment Target** to match the app (iOS 15+ rec.).

## How delivery is confirmed in each app state

| App state | Mechanism | Receipt |
|---|---|---|
| Foreground | plugin `willPresent` → `onForegroundMessage` | `delivered` |
| Background tap / cold-start tap | plugin `didReceive` / `getInitialNotification` | `opened` |
| Terminated (no tap) | **NSE** posts to `/api/sdk/receipts` | `delivered` |

All sends from EngageKaro stamp `ek_message_id` (and `ek_image` for rich push),
which the SDK and NSE read to attribute the receipt.

## Notes

- The plugin sets itself as the `UNUserNotificationCenter` delegate. If you also
  use a library that claims the delegate (e.g. `flutter_local_notifications`),
  you'll need to coordinate — on the recommended iOS-native path you don't.
- APNs `.p8`/Key ID/Team ID/Bundle ID are configured in the EngageKaro dashboard
  (Project → Channels → iOS · APNs); the device never sees them.
