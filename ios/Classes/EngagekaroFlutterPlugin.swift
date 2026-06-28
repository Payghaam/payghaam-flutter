import Flutter
import UIKit
import UserNotifications

/// Native iOS plugin for the EngageKaro Flutter SDK.
///
/// Responsibilities:
///  - Register for remote notifications and surface the raw APNs device token
///    (no Firebase on iOS).
///  - Act as the `UNUserNotificationCenter` delegate to forward foreground
///    arrivals (for `delivered` receipts) and taps (`opened`).
///  - Capture the cold-start notification (tapped from terminated state).
///  - Persist API config to an App Group so the Notification Service Extension
///    can report `delivered` receipts even when the app is killed.
public class EngagekaroFlutterPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  private let tokenHandler = StreamSinkHandler()
  private let openedHandler = StreamSinkHandler()
  private let foregroundHandler = StreamSinkHandler()

  private var currentToken: String?
  private var initialNotification: [String: Any]?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = EngagekaroFlutterPlugin()

    let methods = FlutterMethodChannel(name: "engagekaro/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)

    FlutterEventChannel(name: "engagekaro/onToken", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.tokenHandler)
    FlutterEventChannel(name: "engagekaro/onOpened", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.openedHandler)
    FlutterEventChannel(name: "engagekaro/onForeground", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance.foregroundHandler)

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
    case "setSharedConfig":
      if let args = call.arguments as? [String: Any] { saveSharedConfig(args) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
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

  // MARK: - Helpers

  private func saveSharedConfig(_ args: [String: Any]) {
    guard let appGroup = args["appGroup"] as? String else { return }
    let defaults = UserDefaults(suiteName: appGroup)
    defaults?.set(args["apiBase"] as? String, forKey: "engagekaro.apiBase")
    defaults?.set(args["apiKey"] as? String, forKey: "engagekaro.apiKey")
    defaults?.set(args["externalId"] as? String, forKey: "engagekaro.externalId")
    defaults?.set(args["identityHash"] as? String, forKey: "engagekaro.identityHash")
  }

  /// Convert APNs userInfo into a Flutter-codec-safe `[String: Any]`.
  private static func jsonSafe(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in userInfo {
      if let k = key as? String { out[k] = value }
    }
    return out
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
