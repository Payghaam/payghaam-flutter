package com.payghaam.payghaam_flutter

import com.payghaam.sdk.Payghaam
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives FCM messages. Delegates notification-building and `delivered`-receipt
 * reporting to the canonical Android SDK (`com.payghaam.sdk.Payghaam`) instead
 * of reimplementing them — see sdk-native-wrapper-design.md.
 *
 * [Payghaam.restoreIfNeeded] covers the case where FCM starts this process to
 * deliver a push with the Dart engine never having run (so Dart's `initialize()`,
 * which only reaches this Kotlin code via [PayghaamFlutterPlugin.saveSharedConfig],
 * never fired in *this* process instance).
 */
class PayghaamFirebaseMessagingService : FirebaseMessagingService() {

  override fun onNewToken(token: String) {
    PayghaamFlutterPlugin.emitToken(token)
  }

  override fun onMessageReceived(message: RemoteMessage) {
    Payghaam.restoreIfNeeded(applicationContext)
    // Draws the notification, reports `delivered`, and — via the
    // onMessageReceivedHook wired in PayghaamFlutterPlugin — forwards the raw
    // payload to Dart's onForeground stream.
    Payghaam.handleRemoteMessage(applicationContext, message)
  }
}
