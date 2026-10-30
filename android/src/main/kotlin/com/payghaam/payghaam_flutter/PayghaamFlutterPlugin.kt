package com.payghaam.payghaam_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.payghaam.sdk.Payghaam
import com.payghaam.sdk.SubscriptionType
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/// Native Android plugin: FCM token, notification permission, foreground +
/// tap events, cold-start, and shared config for delivered receipts. Mirrors the
/// iOS plugin's method/event channels so one Dart provider serves both platforms.
class PayghaamFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener, PluginRegistry.RequestPermissionsResultListener {

  private lateinit var context: Context
  private lateinit var methods: MethodChannel
  private var activity: Activity? = null
  private var pendingPermission: Result? = null
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    methods = MethodChannel(binding.binaryMessenger, "payghaam/methods")
    methods.setMethodCallHandler(this)
    EventChannel(binding.binaryMessenger, "payghaam/onToken").setStreamHandler(SinkHandler(Channel.TOKEN))
    EventChannel(binding.binaryMessenger, "payghaam/onOpened").setStreamHandler(SinkHandler(Channel.OPENED))
    EventChannel(binding.binaryMessenger, "payghaam/onForeground").setStreamHandler(SinkHandler(Channel.FOREGROUND))
    // Forwards PayghaamFirebaseMessagingService's canonical-SDK-delegated message
    // handling back to Dart. Tap routing ("onOpened") deliberately does NOT go
    // through Payghaam.onNotificationOpened — this plugin already dispatches taps
    // itself via ActivityAware/NewIntentListener below, and wiring both would
    // double-dispatch (and, via Payghaam's own deep-link fallback, could open a
    // campaign link twice).
    Payghaam.onMessageReceivedHook = { payload -> emitForeground(payload) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    Payghaam.onMessageReceivedHook = null
    scope.cancel()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    @Suppress("UNCHECKED_CAST")
    val args = call.arguments as? Map<String, Any?>
    when (call.method) {
      "requestPermission" -> requestPermission(result)
      "registerForRemoteNotifications" -> result.success(null)
      "getToken" -> {
        try {
          FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            result.success(if (task.isSuccessful) task.result else null)
          }
        } catch (_: Exception) {
          result.success(null)
        }
      }
      "getInitialNotification" -> {
        result.success(initialNotification)
        initialNotification = null
      }
      "getDeviceContext" -> result.success(deviceContext())
      "openUrl" -> result.success(openUrl(call.argument<String>("url")))
      "setSharedConfig" -> {
        if (args != null) saveSharedConfig(context, args)
        result.success(null)
      }
      // ── Cross-platform API bridge (DESIGN.md §4.5) ────────
      "apiSync" -> {
        val apiKey = args?.get("apiKey") as? String
        val baseUrl = args?.get("baseUrl") as? String
        if (apiKey != null && baseUrl != null) {
          Payghaam.persistBridgeConfig(
            context = context,
            apiKey = apiKey,
            baseUrl = baseUrl,
            externalId = args["externalId"] as? String,
            identityHash = args["identityHash"] as? String,
          )
        }
        result.success(null)
      }
      "apiClearIdentity" -> {
        Payghaam.clearBridgeIdentity(context)
        result.success(null)
      }
      "apiIdentify" -> bridgeCall(result) {
        @Suppress("UNCHECKED_CAST")
        val ctx = args?.get("deviceContext") as? Map<String, Any?>
        Payghaam.bridgeIdentify(ctx)
      }
      "apiAddSubscription" -> bridgeCall(result) {
        val type = args?.get("type") as? String ?: return@bridgeCall
        val token = args["token"] as? String ?: return@bridgeCall
        Payghaam.bridgeAddSubscription(
          SubscriptionType.valueOf(type),
          token,
          args["deviceModel"] as? String,
          args["deviceOs"] as? String,
          args["appVersion"] as? String,
        )
      }
      "apiUpdateTags" -> bridgeCall(result) {
        @Suppress("UNCHECKED_CAST")
        val tags = args?.get("tags") as? Map<String, Any?> ?: emptyMap()
        Payghaam.addTags(tags)
      }
      "apiTrack" -> bridgeCall(result) {
        val name = args?.get("name") as? String ?: return@bridgeCall
        @Suppress("UNCHECKED_CAST")
        val props = args["properties"] as? Map<String, Any?>
        Payghaam.trackEvent(name, props)
      }
      "apiReportReceipt" -> bridgeCall(result) {
        val messageId = args?.get("messageId") as? String ?: return@bridgeCall
        val event = args["event"] as? String ?: return@bridgeCall
        @Suppress("UNCHECKED_CAST")
        val props = args["properties"] as? Map<String, Any?>
        Payghaam.reportPushReceipt(messageId, event, props)
      }
      "apiFlushQueue" -> bridgeCall(result) { Payghaam.bridgeFlushQueue() }
      else -> result.notImplemented()
    }
  }

  /**
   * Runs [block] on IO, resolving [result] on the main thread. `sendOrQueue`
   * inside the canonical SDK already swallows retryable failures (parks them in
   * the offline queue), so this only ever surfaces a Flutter error for a
   * non-retryable one (e.g. a 4xx) — Dart wraps that back into
   * `PayghaamApiException`.
   */
  private fun bridgeCall(result: Result, block: suspend () -> Unit) {
    scope.launch {
      try {
        block()
        withContext(Dispatchers.Main) { result.success(null) }
      } catch (t: Throwable) {
        withContext(Dispatchers.Main) {
          // `details` carries the status code (if any) so Dart can reconstruct a
          // proper PayghaamApiException instead of parsing the message string.
          val statusCode = (t as? com.payghaam.sdk.PayghaamApiException)?.statusCode
          result.error("payghaam_api_error", t.message ?: t.toString(), statusCode)
        }
      }
    }
  }

  /// Deep-link fallback, used only when the Dart layer sees no app subscriber.
  /// Prefers the current activity so the link opens in the app's own task.
  private fun openUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
    val host = activity
    return try {
      if (host != null) {
        host.startActivity(intent)
      } else {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
      }
      true
    } catch (_: android.content.ActivityNotFoundException) {
      false
    }
  }

  private fun requestPermission(result: Result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      val act = activity ?: run { result.success(false); return }
      if (act.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
        == PackageManager.PERMISSION_GRANTED) {
        result.success(true)
        return
      }
      pendingPermission = result
      ActivityCompat.requestPermissions(
        act, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST_CODE
      )
    } else {
      result.success(true) // permission implicit pre-Android 13
    }
  }

  override fun onRequestPermissionsResult(
    requestCode: Int, permissions: Array<out String>, grantResults: IntArray
  ): Boolean {
    if (requestCode != PERMISSION_REQUEST_CODE) return false
    val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
    pendingPermission?.success(granted)
    pendingPermission = null
    return true
  }

  // MARK: ActivityAware (read launch/new intents for taps)

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addOnNewIntentListener(this)
    binding.addRequestPermissionsResultListener(this)
    handleIntent(binding.activity.intent)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addOnNewIntentListener(this)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() { activity = null }
  override fun onDetachedFromActivity() { activity = null }

  override fun onNewIntent(intent: Intent): Boolean {
    handleIntent(intent)
    return false
  }

  private fun handleIntent(intent: Intent?) {
    if (intent == null || !intent.getBooleanExtra("ek_opened", false)) return
    val data = HashMap<String, Any?>()
    intent.extras?.keySet()?.forEach { k ->
      if (k != "ek_opened") data[k] = intent.extras?.getString(k)
    }
    emitOpened(data)
    intent.removeExtra("ek_opened")
  }

  private fun deviceContext(): Map<String, String> {
    val locale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      context.resources.configuration.locales[0]
    } else {
      @Suppress("DEPRECATION")
      context.resources.configuration.locale
    }
    val appVersion = try {
      context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
    } catch (_: PackageManager.NameNotFoundException) {
      ""
    }
    return mapOf(
      "country" to locale.country,
      "language" to locale.language,
      "timezone" to java.util.TimeZone.getDefault().id,
      "os" to "Android",
      "osVersion" to Build.VERSION.RELEASE,
      "appVersion" to appVersion,
      "deviceModel" to Build.MODEL,
      "sdkVersion" to "0.1.0",
    )
  }

  internal enum class Channel { TOKEN, OPENED, FOREGROUND }

  private class SinkHandler(val channel: Channel) : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = attachSink(channel, events)
    override fun onCancel(arguments: Any?) = attachSink(channel, null)
  }

  companion object {
    private const val PERMISSION_REQUEST_CODE = 8094

    private val handler = Handler(Looper.getMainLooper())
    private var tokenSink: EventChannel.EventSink? = null
    private var openedSink: EventChannel.EventSink? = null
    private var foregroundSink: EventChannel.EventSink? = null
    private val tokenBuffer = ArrayList<Any>()
    private val openedBuffer = ArrayList<Any>()
    private val foregroundBuffer = ArrayList<Any>()

    @JvmStatic
    var initialNotification: Map<String, Any?>? = null

    fun emitToken(token: String) = handler.post {
      tokenSink?.success(token) ?: tokenBuffer.add(token)
    }

    fun emitForeground(data: Map<String, Any?>) = handler.post {
      foregroundSink?.success(data) ?: foregroundBuffer.add(data)
    }

    fun emitOpened(data: Map<String, Any?>) = handler.post {
      val s = openedSink
      if (s != null) s.success(data) else initialNotification = data
    }

    /**
     * One sink per channel. That is only safe because the Dart side shares a single
     * cached stream per channel (see native_push_provider.dart) — if two Dart
     * subscriptions were ever opened against the same channel, the second `listen`
     * would land here and silently orphan the first. That exact bug stopped the SDK
     * reporting `opened` receipts when a host app subscribed to
     * `onNotificationOpened` after `initialize()`.
     */
    private fun attachSink(channel: Channel, sink: EventChannel.EventSink?) {
      when (channel) {
        Channel.TOKEN -> { tokenSink = sink; if (sink != null) { tokenBuffer.forEach { sink.success(it) }; tokenBuffer.clear() } }
        Channel.OPENED -> {
          openedSink = sink
          if (sink != null) {
            openedBuffer.forEach { sink.success(it) }
            openedBuffer.clear()
            // A tap that cold-started the app is stashed here by emitOpened before
            // Dart could subscribe. Hand it over now rather than relying solely on
            // getInitialNotification, so the receipt fires either way.
            initialNotification?.let { pending ->
              initialNotification = null
              sink.success(pending)
            }
          }
        }
        Channel.FOREGROUND -> { foregroundSink = sink; if (sink != null) { foregroundBuffer.forEach { sink.success(it) }; foregroundBuffer.clear() } }
      }
    }

    /**
     * Persists config for headless FCM handling by delegating to the canonical SDK
     * ([Payghaam.persistBridgeConfig]) instead of maintaining a separate
     * SharedPreferences store — see DESIGN.md. Dart calls this via
     * `push.shareConfig(...)` once after `initialize()`/`login()`.
     */
    fun saveSharedConfig(context: Context, args: Map<String, Any?>) {
      val apiBase = args["apiBase"] as? String ?: return
      val apiKey = args["apiKey"] as? String ?: return
      Payghaam.persistBridgeConfig(
        context = context,
        apiKey = apiKey,
        baseUrl = apiBase,
        externalId = args["externalId"] as? String,
        identityHash = args["identityHash"] as? String,
      )
    }
  }
}
