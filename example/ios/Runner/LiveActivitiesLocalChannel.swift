import ActivityKit
import Flutter
import Foundation

/// Host-side ActivityKit helpers for local start/update/end from Dart.
///
/// The Flutter plugin does **not** encode arbitrary `ActivityAttributes` —
/// ActivityKit is typed. Wire this channel in AppDelegate (see example) after
/// `PayghaamLiveActivities.observe(DeliveryAttributes.self)`.
@available(iOS 16.1, *)
enum LiveActivitiesLocalChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "payghaam/liveActivitiesLocal",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "startActivity":
        start(call: call, result: result)
      case "updateActivity":
        Task { await update(call: call, result: result) }
      case "endActivity":
        Task { await end(call: call, result: result) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func start(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let orderId = args["orderId"] as? String else {
      result(FlutterError(code: "bad_args", message: "orderId required", details: nil))
      return
    }
    let stage = args["stage"] as? String ?? "picked_up"
    let eta = (args["etaMinutes"] as? NSNumber)?.intValue ?? 30
    let attrs = DeliveryAttributes(orderId: orderId)
    let state = DeliveryAttributes.ContentState(stage: stage, etaMinutes: eta)

    do {
      let activity: Activity<DeliveryAttributes>
      if #available(iOS 16.2, *) {
        activity = try Activity.request(
          attributes: attrs,
          content: ActivityContent(state: state, staleDate: nil),
          pushType: .token
        )
      } else {
        activity = try Activity.request(
          attributes: attrs,
          contentState: state,
          pushType: .token
        )
      }
      result(activity.id)
    } catch {
      result(FlutterError(code: "start_failed", message: "\(error)", details: nil))
    }
  }

  private static func update(call: FlutterMethodCall, result: @escaping FlutterResult) async {
    guard let activity = findActivity(args: call.arguments as? [String: Any]) else {
      result(false)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let stage = args["stage"] as? String,
          let eta = (args["etaMinutes"] as? NSNumber)?.intValue else {
      result(FlutterError(code: "bad_args", message: "stage and etaMinutes required", details: nil))
      return
    }
    let state = DeliveryAttributes.ContentState(stage: stage, etaMinutes: eta)
    if #available(iOS 16.2, *) {
      await activity.update(ActivityContent(state: state, staleDate: nil))
    } else {
      await activity.update(using: state)
    }
    result(true)
  }

  private static func end(call: FlutterMethodCall, result: @escaping FlutterResult) async {
    guard let activity = findActivity(args: call.arguments as? [String: Any]) else {
      result(false)
      return
    }
    let args = call.arguments as? [String: Any]
    let stage = args?["stage"] as? String ?? "delivered"
    let eta = (args?["etaMinutes"] as? NSNumber)?.intValue ?? 0
    let state = DeliveryAttributes.ContentState(stage: stage, etaMinutes: eta)
    if #available(iOS 16.2, *) {
      await activity.end(
        ActivityContent(state: state, staleDate: nil),
        dismissalPolicy: .immediate
      )
    } else {
      await activity.end(using: state, dismissalPolicy: .immediate)
    }
    result(true)
  }

  private static func findActivity(args: [String: Any]?) -> Activity<DeliveryAttributes>? {
    guard let args else { return nil }
    if let kitId = args["activityId"] as? String {
      return Activity<DeliveryAttributes>.activities.first { $0.id == kitId }
    }
    if let orderId = args["orderId"] as? String {
      let handle = "order-\(orderId)"
      return Activity<DeliveryAttributes>.activities.first {
        $0.attributes.payghaamActivityId == handle
      }
    }
    return nil
  }
}
