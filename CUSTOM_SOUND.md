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
- **Android (FCM):** `android.notification.sound` = `soundAndroid`, and the same
  value is mirrored in the data payload as `ek_sound` so the SDK's own
  notification builder can read it.

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

2. **Create a channel for that sound and route to it.** The SDK's
   `EngagekaroFirebaseMessagingService` builds the notification itself and reads
   `ek_sound` from the data payload. Extend `showNotification` to map that name
   to a per-sound channel:

   ```kotlin
   val soundName = message.data["ek_sound"]           // e.g. "chime"
   val channelId = if (soundName.isNullOrBlank()) "engagekaro_default"
                   else "engagekaro_sound_$soundName"

   if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
       nm.getNotificationChannel(channelId) == null) {
     val channel = NotificationChannel(
       channelId, "Notifications", NotificationManager.IMPORTANCE_HIGH,
     )
     if (!soundName.isNullOrBlank()) {
       // soundAndroid arrives already extension-free (a res/raw resource name).
       val uri = Uri.parse("android.resource://$packageName/raw/$soundName")
       val attrs = AudioAttributes.Builder()
         .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
         .setUsage(AudioAttributes.USAGE_NOTIFICATION)
         .build()
       channel.setSound(uri, attrs)
     }
     nm.createNotificationChannel(channel)
   }
   ```

   On **Android 7 and below** there are no channels; call
   `builder.setSound(uri)` on the `Notification.Builder` instead.

3. **Keep names stable.** Because a channel's sound is locked after creation,
   pick a sound name per channel and don't reuse the same channel id with a
   different file — bump the name (`chime`, `chime_v2`) if you change the audio.

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
