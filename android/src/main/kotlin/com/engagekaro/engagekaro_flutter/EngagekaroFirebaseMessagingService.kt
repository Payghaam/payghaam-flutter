package com.engagekaro.engagekaro_flutter

import com.engagekaro.sdk.EngageKaro
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives FCM messages. Delegates notification-building and `delivered`-receipt
 * reporting to the canonical Android SDK (`com.engagekaro.sdk.EngageKaro`) instead
 * of reimplementing them — see sdk-native-wrapper-design.md.
 *
 * [EngageKaro.restoreIfNeeded] covers the case where FCM starts this process to
 * deliver a push with the Dart engine never having run (so Dart's `initialize()`,
 * which only reaches this Kotlin code via [EngagekaroFlutterPlugin.saveSharedConfig],
 * never fired in *this* process instance).
 */
class EngagekaroFirebaseMessagingService : FirebaseMessagingService() {

  override fun onNewToken(token: String) {
    EngagekaroFlutterPlugin.emitToken(token)
  }

  override fun onMessageReceived(message: RemoteMessage) {
    EngageKaro.restoreIfNeeded(applicationContext)
    // Draws the notification, reports `delivered`, and — via the
    // onMessageReceivedHook wired in EngagekaroFlutterPlugin — forwards the raw
    // payload to Dart's onForeground stream.
    EngageKaro.handleRemoteMessage(applicationContext, message)
  }
}
