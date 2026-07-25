# Custom notification sounds

EngageKaro lets you attach a **custom sound** to a push notification. Set it in
the dashboard (campaign composer or a journey **Send push** node → *Custom
sound*), or send it via the API.

Because iOS and Android name sounds differently, there are **two separate
fields** — fill in whichever platforms you target:

| Field | Platform | Format | Example |
| --- | --- | --- | --- |
| `soundIos` | iOS (APNs) | filename **with** extension | `chime.caf` |
| `soundAndroid` | Android (FCM) | `res/raw` resource name, **no** extension | `chime` |

> **EngageKaro only carries the sound _name_.** The actual audio file has to ship
> inside your app — it can't be streamed from a URL. iOS and Android both require
> the file to be bundled/registered ahead of time. This page covers that setup.

What EngageKaro puts on the wire:

- **iOS (APNs):** `aps.sound` = `soundIos`.
- **Android (FCM):** `ek_sound` = `soundAndroid`, in the data payload. Android
  pushes are sent data-only (so the SDK can attach deep links to the tap), which
  means FCM never draws the notification and `android.notification.sound` would
  have nothing to apply to. The SDK's own builder reads `ek_sound` instead and
  routes the notification to a channel carrying that sound — in every app state,
  foreground included.

(`sound` — a single legacy value — is still honored as a fallback for either
platform when the platform-specific field is empty.) Leave a field blank and that
platform uses the system default sound.

---

## iOS

1. **Add the sound file to the app target.** Drag a short audio file into your
   Xcode project and make sure it's in **Build Phases → Copy Bundle Resources**
   of the _main app target_ (not the Notification Service Extension).

   - Supported formats: `.caf`, `.aiff`, `.wav`, or `.mp3` (Linear PCM, MA4,
     µ-law, or a-law).
   - Must be **30 seconds or shorter**, or iOS silently falls back to the
     default sound.

2. **Enter the filename _with extension_** in the EngageKaro **iOS sound** field,
   e.g. `chime.caf`. This is the value APNs matches against the bundled file.

That's it — the OS plays the sound from `aps.sound` automatically. No extension
or code changes are required, because the sound comes from the app bundle, not
the notification payload.

---

## Android

Android is stricter: on **Android 8+ (API 26)** the sound is a property of the
**notification channel** and is fixed when the channel is first created — you
can't change a channel's sound per-notification. So "custom sound per message"
means routing the message to a channel that already has that sound.

1. **Add the sound file to `res/raw`.** Place it at
   `android/app/src/main/res/raw/chime.mp3` (or `.ogg` / `.wav`). The resource
   name is the filename **without** extension (`chime`) and must be lowercase
   with no spaces. Enter that name (`chime`) in the EngageKaro **Android sound**
   field.

2. **That's it — the SDK handles the channel.** `EngagekaroFirebaseMessagingService`
   reads `ek_sound`, resolves it against `res/raw`, and posts to a channel
   dedicated to that sound (`engagekaro_default_sound_chime`), creating it on
   first use. On **Android 7 and below**, where channels don't exist, it calls
   `builder.setSound(uri)` directly.

   If the name doesn't resolve to a bundled `res/raw` file, the SDK falls back to
   the default channel and the system sound — a notification with a broken sound
   URI would otherwise be silent.

3. **Keep names stable.** Because a channel's sound is locked after creation,
   don't ship a different audio file under a name you've already used — bump the
   name (`chime` → `chime_v2`) instead, or existing installs keep the old sound.

---

## Cross-platform checklist

To play a custom sound on both platforms for the same notification:

1. Bundle the iOS file in the app target (e.g. `chime.caf`) and enter it in the
   **iOS sound** field.
2. Add the Android file to `res/raw` (e.g. `chime.mp3`) and enter its
   extensionless name (`chime`) in the **Android sound** field.
3. Wire the Android SDK snippet above so the channel picks up `ek_sound`.

The two fields are independent — filling only one plays a custom sound on that
platform and the default on the other.
