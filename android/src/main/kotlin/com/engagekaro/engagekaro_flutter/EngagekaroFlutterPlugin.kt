package com.engagekaro.engagekaro_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
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

/// Native Android plugin: FCM token, notification permission, foreground +
/// tap events, cold-start, and shared config for delivered receipts. Mirrors the
/// iOS plugin's method/event channels so one Dart provider serves both platforms.
class EngagekaroFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener, PluginRegistry.RequestPermissionsResultListener {

  private lateinit var context: Context
  private lateinit var methods: MethodChannel
  private var activity: Activity? = null
  private var pendingPermission: Result? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    methods = MethodChannel(binding.binaryMessenger, "engagekaro/methods")
    methods.setMethodCallHandler(this)
    EventChannel(binding.binaryMessenger, "engagekaro/onToken").setStreamHandler(SinkHandler(Channel.TOKEN))
    EventChannel(binding.binaryMessenger, "engagekaro/onOpened").setStreamHandler(SinkHandler(Channel.OPENED))
    EventChannel(binding.binaryMessenger, "engagekaro/onForeground").setStreamHandler(SinkHandler(Channel.FOREGROUND))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "requestPermission" -> requestPermission(result)
      "registerForRemoteNotifications" -> result.success(null)
      "getToken" -> FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
        result.success(if (task.isSuccessful) task.result else null)
      }
      "getInitialNotification" -> {
        result.success(initialNotification)
        initialNotification = null
      }
      "getDeviceContext" -> result.success(deviceContext())
      "openUrl" -> result.success(openUrl(call.argument<String>("url")))
      "setSharedConfig" -> {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any?>
        if (args != null) saveSharedConfig(context, args)
        result.success(null)
      }
      else -> result.notImplemented()
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
    const val PREFS = "engagekaro"

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

    fun saveSharedConfig(context: Context, args: Map<String, Any?>) {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
        putString("apiBase", args["apiBase"] as? String)
        putString("apiKey", args["apiKey"] as? String)
        putString("externalId", args["externalId"] as? String)
        putString("identityHash", args["identityHash"] as? String)
        apply()
      }
    }
  }
}
