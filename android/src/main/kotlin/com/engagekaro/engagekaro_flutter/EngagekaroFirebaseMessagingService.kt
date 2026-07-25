package com.engagekaro.engagekaro_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/// Receives FCM messages. Forwards to Dart (foreground), reports `delivered`
/// (even when the app is killed), and shows a tappable notification whose tap
/// routes back to the app as `opened`.
class EngagekaroFirebaseMessagingService : FirebaseMessagingService() {

  override fun onNewToken(token: String) {
    EngagekaroFlutterPlugin.emitToken(token)
  }

  override fun onMessageReceived(message: RemoteMessage) {
    val data = HashMap<String, Any?>(message.data)

    message.data["ek_message_id"]?.let { reportDelivered(it) }
    EngagekaroFlutterPlugin.emitForeground(data)
    showNotification(message)
  }

  private fun showNotification(message: RemoteMessage) {
    val title = message.notification?.title ?: message.data["title"]
    val body = message.notification?.body ?: message.data["body"]
    if (title == null && body == null) return

    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val soundName = message.data["ek_sound"]
    val sound = soundUri(soundName)
    val channelId = ensureChannel(nm, sound, soundName)

    val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
      flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
      putExtra("ek_opened", true)
      for ((k, v) in message.data) putExtra(k, v)
    }
    var piFlags = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) piFlags = piFlags or PendingIntent.FLAG_IMMUTABLE
    val id = notificationId(message)
    val pending = PendingIntent.getActivity(this, id, launch, piFlags)

    @Suppress("DEPRECATION")
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
      Notification.Builder(this, channelId)
    else
      Notification.Builder(this).also { if (sound != null) it.setSound(sound) }

    builder.setContentTitle(title)
      .setContentText(body)
      .setAutoCancel(true)
      .setSmallIcon(applicationInfo.icon)
      .setContentIntent(pending)

    // Rich image. Safe to fetch inline: onMessageReceived already runs off the main
    // thread, and the download is tightly bounded.
    bigPicture(message.data["ek_image"])?.let { bitmap ->
      builder.setLargeIcon(bitmap)
      builder.setStyle(Notification.BigPictureStyle().bigPicture(bitmap))
    }

    nm.notify(id, builder.build())
  }

  /** Downloads the notification image, or null if it can't be had quickly. */
  private fun bigPicture(url: String?): Bitmap? {
    if (url.isNullOrBlank()) return null
    return try {
      val conn = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 5_000
        readTimeout = 5_000
        doInput = true
      }
      try {
        conn.inputStream.use { BitmapFactory.decodeStream(it) }
      } finally {
        conn.disconnect()
      }
    } catch (_: Exception) {
      // An unreachable or malformed image must never cost the notification.
      null
    }
  }

  /**
   * Resolves a `res/raw` resource name to a playable URI, or null when the app ships
   * no such file — a bad URI silences the notification entirely, so an unresolvable
   * name falls back to the system default rather than to nothing.
   */
  private fun soundUri(name: String?): Uri? {
    if (name.isNullOrBlank()) return null
    val resId = resources.getIdentifier(name, "raw", packageName)
    if (resId == 0) return null
    return Uri.parse("android.resource://$packageName/$resId")
  }

  /**
   * Returns the channel to post on, creating it if needed. On Android 8+ the sound
   * belongs to the channel and is immutable once created, so a custom sound means
   * posting to a channel dedicated to that sound.
   */
  private fun ensureChannel(nm: NotificationManager, sound: Uri?, soundName: String?): String {
    val default = "engagekaro_default"
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return default

    val channelId =
      if (sound == null || soundName.isNullOrBlank()) default else "${default}_sound_$soundName"
    if (nm.getNotificationChannel(channelId) != null) return channelId

    val label = if (channelId == default) "Notifications" else "Notifications ($soundName)"
    val channel = NotificationChannel(channelId, label, NotificationManager.IMPORTANCE_HIGH)
    if (sound != null) {
      channel.setSound(
        sound,
        AudioAttributes.Builder()
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
          .setUsage(AudioAttributes.USAGE_NOTIFICATION)
          .build()
      )
    }
    nm.createNotificationChannel(channel)
    return channelId
  }

  private fun notificationId(message: RemoteMessage): Int =
    (message.data["ek_message_id"] ?: message.messageId ?: System.currentTimeMillis().toString()).hashCode()

  /// Report a `delivered` receipt using the natively-stored config (works while
  /// the app is terminated, since FCM starts this service in the app process).
  private fun reportDelivered(messageId: String) {
    val prefs = getSharedPreferences(EngagekaroFlutterPlugin.PREFS, Context.MODE_PRIVATE)
    val apiBase = prefs.getString("apiBase", null) ?: return
    val apiKey = prefs.getString("apiKey", null) ?: return
    val externalId = prefs.getString("externalId", null)
    val identityHash = prefs.getString("identityHash", null)

    Thread {
      try {
        val conn = URL("$apiBase/api/sdk/receipts").openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("Authorization", "Bearer $apiKey")
        identityHash?.let { conn.setRequestProperty("X-EngageKaro-Identity-Hash", it) }
        conn.doOutput = true
        conn.connectTimeout = 5000
        conn.readTimeout = 5000
        val body = JSONObject().apply {
          put("messageId", messageId)
          put("event", "delivered")
          externalId?.let { put("externalId", it) }
        }
        OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
        conn.responseCode
        conn.disconnect()
      } catch (_: Exception) {
      }
    }.start()
  }
}
