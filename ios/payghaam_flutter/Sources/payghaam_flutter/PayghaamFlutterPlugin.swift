import Payghaam
import Flutter
import UIKit
import UserNotifications

/// Native iOS plugin for the Payghaam Flutter SDK.
///
/// Responsibilities:
///  - Register for remote notifications and surface the raw APNs device token
///    (no Firebase on iOS).
///  - Act as the `UNUserNotificationCenter` delegate to forward foreground
///    arrivals (for `delivered` receipts) and taps (`opened`).
///  - Capture the cold-start notification (tapped from terminated state).
///  - Persist API config to an App Group so the Notification Service Extension
///    can report `delivered` receipts even when the app is killed.
///  - Forward background push wakes to payghaam-ios so Live Activity update
///    tokens register while the app is suspended.
///
/// Live Activities: the **host AppDelegate** must call
/// `PayghaamLiveActivities.observe(YourAttributes.self)` once after plugin
/// registration (before `login()`). This plugin does not invent ActivityKit
/// attributes — see the example app's `DeliveryAttributes` + local channel.
public class PayghaamFlutterPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  private let tokenHandler = StreamSinkHandler()
  private let openedHandler = StreamSinkHandler()
  private let foregroundHandler = StreamSinkHandler()
  private let liveActivityUpdateTokenHandler = StreamSinkHandler()
  private let liveActivityStartTokenHandler = StreamSinkHandler()

  private var currentToken: String?
  private var initialNotification: [String: Any]?
  private var liveActivityObserversInstalled = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PayghaamFlutterPlugin()

    let methods = FlutterMethodChannel(name: "payghaam/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)

    let liveActivities = FlutterMethodChannel(
      name: "payghaam/liveActivities",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: liveActivities)

    FlutterEventChannel(name: "payghaam/onToken", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.tokenHandler)
    FlutterEventChannel(name: "payghaam/onOpened", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.openedHandler)
    FlutterEventChannel(name: "payghaam/onForeground", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.foregroundHandler)
    FlutterEventChannel(
      name: "payghaam/liveActivityUpdateToken",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance.liveActivityUpdateTokenHandler)
    FlutterEventChannel(
      name: "payghaam/liveActivityStartToken",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance.liveActivityStartTokenHandler)

    instance.installLiveActivityNotificationObservers()

    registrar.addApplicationDelegate(instance)
    UNUserNotificationCenter.current().delegate = instance
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
          result(granted)
        }
      }
    case "registerForRemoteNotifications":
      DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
      result(nil)
    case "getToken":
      result(currentToken)
    case "getInitialNotification":
      let n = initialNotification
      initialNotification = nil
      result(n)
    case "getDeviceContext":
      result(Self.deviceContext())
    case "openUrl":
      // Deep-link fallback, used only when the Dart layer sees no app subscriber.
      guard let args = call.arguments as? [String: Any],
            let raw = args["url"] as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        guard UIApplication.shared.canOpenURL(url) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    case "setSharedConfig":
      if let args = call.arguments as? [String: Any] { saveSharedConfig(args) }
      result(nil)

    // ── Live Activities (thin wrappers over payghaam-ios) ──
    case "refresh":
      if #available(iOS 16.1, *) {
        PayghaamLiveActivities.refreshAll()
      }
      result(nil)

    // ── Cross-platform API bridge (DESIGN.md §4.5) ─────────
    // Proxies a single call through the canonical ApiClient + offline queue,
    // replacing this plugin's old `package:http`-based ApiClient in Dart.
    case "apiSync":
      let args = call.arguments as? [String: Any]
      if let apiKey = args?["apiKey"] as? String, let baseUrl = args?["baseUrl"] as? String {
        MainActor.assumeIsolated {
          Payghaam.shared.persistBridgeConfig(
            apiKey: apiKey,
            baseUrl: baseUrl,
            externalId: args?["externalId"] as? String,
            identityHash: args?["identityHash"] as? String
          )
        }
      }
      result(nil)
    case "apiClearIdentity":
      MainActor.assumeIsolated { Payghaam.shared.clearBridgeIdentity() }
      result(nil)
    case "apiIdentify":
      let ctx = (call.arguments as? [String: Any])?["deviceContext"] as? [String: Any]
      Task {
        do {
          try await Payghaam.shared.bridgeIdentify(deviceContext: ctx)
          result(nil)
        } catch {
          result(Self.apiError(error))
        }
      }
    case "apiAddSubscription":
      guard let args = call.arguments as? [String: Any],
            let typeStr = args["type"] as? String,
            let type = SubscriptionType(rawValue: typeStr),
            let token = args["token"] as? String else {
        result(nil)
        return
      }
      Task {
        do {
          try await Payghaam.shared.bridgeAddSubscription(type: type, token: token)
          result(nil)
        } catch {
          result(Self.apiError(error))
        }
      }
    case "apiUpdateTags":
      let raw = (call.arguments as? [String: Any])?["tags"] as? [String: Any] ?? [:]
      Task {
        do {
          try await Payghaam.shared.addTags(Self.nilCoalesced(raw))
          result(nil)
        } catch {
          result(Self.apiError(error))
        }
      }
    case "apiTrack":
      guard let args = call.arguments as? [String: Any], let name = args["name"] as? String else {
        result(nil)
        return
      }
      let properties = args["properties"] as? [String: Any]
      Task {
        do {
          try await Payghaam.shared.trackEvent(name, properties: properties)
          result(nil)
        } catch {
          result(Self.apiError(error))
        }
      }
    case "apiReportReceipt":
      guard let args = call.arguments as? [String: Any],
            let messageId = args["messageId"] as? String,
            let event = args["event"] as? String else {
        result(nil)
        return
      }
      let properties = args["properties"] as? [String: Any]
      Task {
        await Payghaam.shared.reportPushReceipt(messageId: messageId, event: event, properties: properties)
        result(nil)
      }
    case "apiFlushQueue":
      Task {
        await Payghaam.shared.bridgeFlushQueue()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Converts a Flutter-bridged `[String: Any]` (where a Dart `null` value
  /// arrives as `NSNull`, not Swift `nil`) into `[String: Any?]` so
  /// `Payghaam.addTags` sees real `nil`s for tag removal.
  private static func nilCoalesced(_ dict: [String: Any]) -> [String: Any?] {
    var out: [String: Any?] = [:]
    for (k, v) in dict {
      if v is NSNull {
        out[k] = nil
      } else {
        out[k] = v
      }
    }
    return out
  }

  /// `sendOrQueue` inside the canonical SDK already swallows retryable failures
  /// (parks them in the offline queue), so this only ever surfaces a
  /// FlutterError for a non-retryable one (e.g. a 4xx) — Dart wraps that back
  /// into `PayghaamApiException`. `details` carries the status code so Dart
  /// doesn't have to parse it out of the message.
  private static func apiError(_ error: Error) -> FlutterError {
    if let apiError = error as? PayghaamApiError {
      return FlutterError(code: "payghaam_api_error", message: apiError.errorDescription, details: apiError.statusCode)
    }
    return FlutterError(code: "payghaam_api_error", message: "\(error)", details: nil)
  }

  // MARK: - APNs token (forwarded by FlutterAppDelegate)

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    currentToken = token
    tokenHandler.send(token)
  }

  // MARK: - Push wake → Live Activity token refresh (payghaam-ios)

  /// FlutterAppDelegate forwards remote notifications to plugins that return
  /// `true`. We call payghaam-ios, which invokes `completionHandler` itself.
  public func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    // Payghaam is @MainActor; UIKit may invoke this delegate off the main thread
    // during a background wake. Hop to the main actor before calling through.
    Task { @MainActor in
      Payghaam.shared.handleRemoteNotification(userInfo, fetchCompletionHandler: completionHandler)
    }
    return true
  }

  // MARK: - UNUserNotificationCenterDelegate

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    foregroundHandler.send(Self.jsonSafe(notification.request.content.userInfo))
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let data = Self.jsonSafe(response.notification.request.content.userInfo)
    if openedHandler.hasListener {
      openedHandler.send(data)
    } else {
      // App was launched from terminated by this tap — surface via getInitialNotification.
      initialNotification = data
    }
    completionHandler()
  }

  // MARK: - Live Activity notification bridge

  private func installLiveActivityNotificationObservers() {
    guard !liveActivityObserversInstalled else { return }
    liveActivityObserversInstalled = true

    NotificationCenter.default.addObserver(
      forName: .payghaamLiveActivityUpdateToken,
      object: nil,
      queue: .main
    ) { [weak self] note in
      self?.liveActivityUpdateTokenHandler.send(Self.jsonSafe(note.userInfo ?? [:]))
    }
    NotificationCenter.default.addObserver(
      forName: .payghaamLiveActivityStartToken,
      object: nil,
      queue: .main
    ) { [weak self] note in
      self?.liveActivityStartTokenHandler.send(Self.jsonSafe(note.userInfo ?? [:]))
    }
  }

  // MARK: - Helpers

  private func saveSharedConfig(_ args: [String: Any]) {
    guard let appGroup = args["appGroup"] as? String else { return }
    let defaults = UserDefaults(suiteName: appGroup)
    defaults?.set(args["apiBase"] as? String, forKey: "payghaam.apiBase")
    defaults?.set(args["apiKey"] as? String, forKey: "payghaam.apiKey")
    defaults?.set(args["externalId"] as? String, forKey: "payghaam.externalId")
    defaults?.set(args["identityHash"] as? String, forKey: "payghaam.identityHash")
  }

  /// Convert APNs userInfo into a Flutter-codec-safe `[String: Any]`.
  private static func jsonSafe(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in userInfo {
      if let k = key as? String { out[k] = value }
    }
    return out
  }

  /// Delegates to the canonical SDK (sdks/ios) instead of duplicating the
  /// locale/UIDevice snapshot — see DESIGN.md. Note this
  /// omits `pushPermission`/`sessionStart`; the Dart layer requests those
  /// separately and merges them before sending, matching its existing
  /// behavior on Android. `Payghaam` is @MainActor; assumeIsolated is safe
  /// because Flutter dispatches method channel calls on the platform (main)
  /// thread by default, and this plugin doesn't set a custom task queue.
  private static func deviceContext() -> [String: Any] {
    MainActor.assumeIsolated { Payghaam.deviceContextSnapshot() }
  }
}

/// Buffers events until a Dart listener attaches, so startup events aren't lost.
private class StreamSinkHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var buffer: [Any] = []

  var hasListener: Bool { sink != nil }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    for e in buffer { events(e) }
    buffer.removeAll()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func send(_ value: Any) {
    if let s = sink {
      s(value)
    } else {
      buffer.append(value)
    }
  }
}
