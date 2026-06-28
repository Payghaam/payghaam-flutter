# Android setup (native FCM, no firebase_messaging plugin)

`engagekaro_flutter` includes native Kotlin that talks to FCM directly. You do
**not** add the `firebase_messaging` Flutter plugin — but FCM still needs a
Firebase project + `google-services.json`, like any Android push integration.

## 1. Firebase project + google-services.json

1. Create (or reuse) a Firebase project and add your Android app (package name
   must match your app's `applicationId`).
2. Download `google-services.json` into `android/app/`.
3. Upload the matching **FCM service-account JSON** to EngageKaro
   (Dashboard → Project → Channels → Android · FCM). EngageKaro sends through
   FCM using that; the device never sees it.

## 2. Gradle wiring

`android/build.gradle` (project-level) — add the Google services classpath:

```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

`android/app/build.gradle` — apply the plugin (top or bottom):

```gradle
apply plugin: 'com.google.gms.google-services'
```

The EngageKaro plugin already pulls in `firebase-messaging`, so you don't add it
yourself. Make sure your app `minSdkVersion` is ≥ 21.

## 3. Use it (same code as iOS)

```dart
final push = EngageKaroPushProvider();
await EngageKaro.instance.initialize(config, push: push);
await EngageKaro.instance.login('user-id');
await EngageKaro.instance.requestPushPermission(); // shows the Android 13+ prompt

await push.shareConfig(
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'user-id',
);
```

## How delivery is confirmed in each app state (Android)

| App state | Mechanism | Receipt |
|---|---|---|
| Foreground | `EngagekaroFirebaseMessagingService.onMessageReceived` → `onForegroundMessage` | `delivered` |
| Tap (background/terminated) | notification `PendingIntent` → plugin `onNewIntent` / `getInitialNotification` | `opened` |
| Data message while terminated | the service posts to `/api/sdk/receipts` | `delivered` |

For reliable terminated-state `delivered`, EngageKaro sends **data** messages
that include `ek_message_id` (the worker already does this).

## Notes

- The plugin shows notifications via its own `engagekaro_default` channel and a
  default small icon (`applicationInfo.icon`). Supply a proper monochrome
  notification icon for production.
- Android 13+ requires the runtime `POST_NOTIFICATIONS` permission, which
  `requestPushPermission()` triggers.
