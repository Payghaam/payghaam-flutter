# iOS setup (direct APNs, no Firebase)

The Payghaam Flutter SDK ships native iOS code that registers for APNs, gets
the device token, and handles notification taps/foreground. A Notification
Service Extension (NSE) adds terminated-state **confirmed delivery** and rich
images. Android push is handled natively too (see
[ANDROID_SETUP.md](./ANDROID_SETUP.md)), but these steps are iOS only.

## Automate setup (recommended)

From your Flutter **app** root:

```bash
dart run payghaam_flutter:install
# or only iOS:
dart run payghaam_flutter:install --ios
# optional:
dart run payghaam_flutter:install --ios --app-group=group.com.yourcompany.app.payghaam --dry-run
```

The CLI (idempotent, safe to re-run) writes:

- Runner: Push Notifications (`aps-environment`), Background Modes →
  `remote-notification`, App Group `group.<bundle_id>.payghaam` (or `--app-group`)
- `PayghaamAppGroup` in Runner and NSE `Info.plist`
- A `PayghaamNSE` Notification Service Extension target in `ios/Runner.xcodeproj`
- `ios_extension/NotificationService.swift` copied from this package into that target
- CocoaPods `target 'PayghaamNSE' do pod 'Payghaam' end` when a Podfile exists,
  or the Payghaam iOS SDK as an SPM dependency of `PayghaamNSE` when it does not

Still manual: upload an APNs Auth Key (`.p8`) plus Key ID, Team ID, and Bundle ID
in the Payghaam dashboard → Project → Channels → iOS · APNs; enable the App Group
on the App ID if Xcode signing asks; call `shareConfig(appGroup: …)` after
`login()` (see below).

The rest of this file is the click-through Xcode path if you prefer to do it
yourself.

## 1. App capabilities (main app target)

In Xcode → your app target → **Signing & Capabilities**, add:

- **Push Notifications**
- **Background Modes** → enable **Remote notifications**
- **App Groups** → add a group id, e.g. `group.com.yourcompany.app.payghaam`

> Use an App Group id unique to this app. Don't reuse one across multiple apps
> you own — the app and NSE share a container through it, and a shared id lets
> unrelated apps read each other's queued data.

## 2. Tell the app + extension the App Group

Add this key to the **app target's** `Info.plist` (and the NSE's later):

```xml
<key>PayghaamAppGroup</key>
<string>group.com.yourcompany.app.payghaam</string>
```

## 3. Use the provider in Dart (same code on iOS and Android)

```dart
import 'package:payghaam_flutter/payghaam_flutter.dart';

final config = PayghaamConfig(
  appId: 'YOUR_PROJECT_ID',
  apiKey: 'ek_client_...',
  baseUrl: 'https://api.yourhost.com',
);

final push = PayghaamPushProvider();
await Payghaam.instance.initialize(config, push: push);
await Payghaam.instance.login('your-user-id');
await Payghaam.instance.requestPushPermission();

// Share config with the NSE so it can report delivery while terminated.
await push.shareConfig(
  appGroup: 'group.com.yourcompany.app.payghaam', // iOS only; Android ignores it
  apiBase: config.baseUrl,
  apiKey: config.apiKey,
  externalId: 'your-user-id',
);
```

> Build and run now, before adding the NSE. Confirming you get a device token
> and a test push delivers here isolates basic APNs setup from NSE-specific
> issues (App Group mismatch, target wiring) in the next step.

## 4. Add the Notification Service Extension

1. Xcode → **File ▸ New ▸ Target… ▸ Notification Service Extension**. Name it
   e.g. `PayghaamNSE`. Don't activate the scheme.
2. Replace the generated `NotificationService.swift` with
   [`ios_extension/NotificationService.swift`](./ios_extension/NotificationService.swift).
   It calls into the canonical `Payghaam` package (`import Payghaam`), so
   add that as a dependency of the **new NSE target** — Xcode → NSE target →
   **General → Frameworks and Libraries → +** (if using CocoaPods, add a
   `target 'PayghaamNSE' do pod 'Payghaam', :path => '...' end` block to
   your Podfile and re-run `pod install` instead).
3. NSE target → **Signing & Capabilities** → add **App Groups** → the **same**
   group id as the app.
4. NSE target → `Info.plist` → add the same `PayghaamAppGroup` key/value.
5. Set the NSE **Minimum Deployment Target** to match the app (iOS 15+ rec.).

## How delivery is confirmed in each app state

| App state | Mechanism | Receipt |
|---|---|---|
| Foreground | plugin `willPresent` → `onForegroundMessage` | `delivered` |
| Background tap / cold-start tap | plugin `didReceive` / `getInitialNotification` | `opened` |
| Terminated (no tap) | **NSE** posts to `/api/sdk/receipts` | `delivered` |

All sends from Payghaam stamp `ek_message_id` (and `ek_image` for rich push),
which the SDK and NSE read to attribute the receipt.

## Notes

- The plugin sets itself as the `UNUserNotificationCenter` delegate. If you also
  use a library that claims the delegate (e.g. `flutter_local_notifications`),
  you'll need to coordinate — on the recommended iOS-native path you don't.
- APNs is configured entirely in the Payghaam dashboard — the device never
  sees your APNs credentials:
  1. In the Apple Developer portal (Certificates, Identifiers & Profiles →
     Keys), generate an APNs Auth Key (`.p8`) and note its Key ID.
  2. Find your Team ID in the Apple Developer portal (Membership).
  3. In the Payghaam dashboard → Project → Channels → iOS · APNs, upload the
     `.p8` and enter the Key ID, Team ID, and your app's Bundle ID.
  4. Save. Payghaam signs and sends pushes through APNs using these
     credentials.

## Troubleshooting

**No `delivered` receipt while terminated, only `opened` on tap.**
Cause: the NSE isn't running — usually an App Group mismatch. Fix: compare
the App Group id in all four places it's set (app target capabilities, app
`Info.plist`, NSE target capabilities, NSE `Info.plist`) — a typo in any one
silently breaks the shared container the NSE reads from.

**NSE target fails to build with `Payghaam` (or `import Payghaam`) not found.**
Cause: Xcode doesn't share the app target's dependencies with extension
targets, so the NSE needs its own. Fix: add `Payghaam` under the NSE target's
**Frameworks and Libraries** (SPM), or for CocoaPods add a
`target 'PayghaamNSE' do pod 'Payghaam', :path => '...' end` block to the
Podfile and re-run `pod install`.

**Tapping a push with an `ek_url` deep link opens the app but never navigates.**
Cause: no URL Type is registered for the scheme, so `openURL` has nowhere to
route it — the fallback described in the [README](./README.md#handling-taps-and-deep-links)
needs a claimed scheme to work. Fix: Xcode → app target → **Info** → **URL
Types** → **+**, and add a `CFBundleURLTypes` entry matching the scheme used
in the campaign's Deep link URL.
