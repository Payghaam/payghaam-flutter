package com.engagekaro.engagekaro_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
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

    val channelId = "engagekaro_default"
    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
      nm.getNotificationChannel(channelId) == null) {
      nm.createNotificationChannel(
        NotificationChannel(channelId, "Notifications", NotificationManager.IMPORTANCE_HIGH)
      )
    }

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
      Notification.Builder(this)

    builder.setContentTitle(title)
      .setContentText(body)
      .setAutoCancel(true)
      .setSmallIcon(applicationInfo.icon)
      .setContentIntent(pending)

    nm.notify(id, builder.build())
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
