# Android setup (native FCM, no firebase_messaging plugin)

`payghaam_flutter` includes native Kotlin that talks to FCM directly. You do
**not** add the `firebase_messaging` Flutter plugin — but FCM still needs a
Firebase project + `google-services.json`, like any Android push integration.

## 1. Firebase project + google-services.json

1. Create (or reuse) a Firebase project and add your Android app (package name
   must match your app's `applicationId`).
2. Download `google-services.json` into `android/app/`.
3. Upload the matching **FCM service-account JSON** to Payghaam:
   1. Firebase console → **Project settings → Service accounts** → generate
      a new private key (downloads a JSON file).
   2. Payghaam dashboard → **Project → Channels → Android · FCM** → upload
      that JSON.
   3. Save. Payghaam sends through FCM using that service account; the
      device never sees it.

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

The plugin depends on the canonical native Android SDK (`com.payghaam:payghaam`
at `sdks/android`), which pulls in `firebase-messaging` transitively — you don't
add either yourself. Make sure your app `minSdkVersion` is ≥ 21 and JVM target is
17 (the native SDK's own target — a lower one won't compile against it).

That native SDK isn't published to Maven yet, so until it is, point your app's
`android/settings.gradle.kts` at it with a composite build + dependency
substitution (adjust the relative path to wherever you've checked out this repo):

```kotlin
includeBuild("../../sdks/android") {
    dependencySubstitution {
        substitute(module("com.payghaam:payghaam")).using(project(":payghaam"))
    }
}
```

Once it's published, this block goes away and `com.payghaam:payghaam`
resolves from Maven like any other dependency.

## 3. Use it (same code as iOS)

```dart
final push = PayghaamPushProvider();
await Payghaam.instance.initialize(config, push: push);
await Payghaam.instance.login('user-id');
await Payghaam.instance.requestPushPermission(); // shows the Android 13+ prompt

await push.shareConfig(
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'user-id',
);
```

## 4. Register your deep-link scheme (required for the campaign "Deep link URL")

A URL only opens if some app on the device has claimed its scheme. Nothing claims
`myapp://` by default — not even you — so add a `VIEW` intent-filter to your
launcher activity in `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity" android:launchMode="singleTop" ...>
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>

    <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="myapp"/>
    </intent-filter>
</activity>
```

Then set the campaign's **Deep link URL** to a matching URL (`myapp://offers/summer`).

Without this the tap still opens the app and your `onNotificationOpened` listener
still fires with the payload — only the SDK's automatic `ACTION_VIEW` fallback has
nowhere to go. With `debug: true` in your config the SDK logs exactly that.

Verify the scheme resolves without sending a push:

```bash
adb shell am start -a android.intent.action.VIEW -d "myapp://offers/summer"
```

`https://` URLs need no intent-filter — a browser already claims them — but they
open the browser unless you configure Android App Links with a verified domain.

## How delivery is confirmed in each app state (Android)

| App state | Mechanism | Receipt |
|---|---|---|
| Foreground | `PayghaamFirebaseMessagingService.onMessageReceived` → `onForegroundMessage` | `delivered` |
| Tap (background/terminated) | notification `PendingIntent` → plugin `onNewIntent` / `getInitialNotification` | `opened` |
| Data message while terminated | the service posts to `/api/sdk/receipts` | `delivered` |

For reliable terminated-state `delivered`, Payghaam sends **data** messages
that include `ek_message_id` (the worker already does this).

## Notes

- The plugin shows notifications via its own `payghaam_default` channel and a
  default small icon (`applicationInfo.icon`). Supply a proper monochrome
  notification icon for production.
- Android 13+ requires the runtime `POST_NOTIFICATIONS` permission, which
  `requestPushPermission()` triggers.
- If you enable R8/ProGuard minification, verify push notifications and
  events still work in a release build — this repo has no
  `consumer-rules.pro` to inspect, so whether `com.payghaam:payghaam` ships
  its own consumer rules isn't confirmable from here.

## Troubleshooting

**Build fails with a Kotlin/AGP/JVM version conflict when the native SDK
composite build resolves.**
Cause: the native SDK requires AGP 8.1.0+, Kotlin 1.9.0+, and JVM target 17;
an app on older versions can't compile against it. Fix: bump your app's
`android/build.gradle` (or `build.gradle.kts`) AGP and Kotlin versions, and
set `sourceCompatibility`/`targetCompatibility`/`jvmTarget` to 17 to match.

**No notifications arrive, and there's no error.**
Cause: the `google-services.json` package name doesn't match your app's
`applicationId`, so FCM can't route to it. Fix: confirm `package_name` in
`google-services.json` exactly matches `applicationId` in
`android/app/build.gradle`; regenerate from the Firebase console if it
doesn't.

**Notifications arrive but play the default sound instead of a custom one.**
Cause: the Android notification channel is created once and cached — a
sound change doesn't retroactively apply to a channel that already exists on
a user's device. Fix: bump the channel id (or clear app data / reinstall
during testing) so a fresh channel picks up the new sound. See
[CUSTOM_SOUND.md](./CUSTOM_SOUND.md).
