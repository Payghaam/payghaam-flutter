import ActivityKit
import SwiftUI
import WidgetKit

/// Stub Live Activity UI for the example app.
///
/// **Not wired into the Xcode project by default** — Flutter example targets do
/// not ship a Widget Extension out of the box. To finish setup:
///
/// 1. Xcode → File → New → Target → Widget Extension (e.g. `DeliveryActivity`).
/// 2. Enable **Include Live Activity**.
/// 3. Add this file + `../Runner/DeliveryAttributes.swift` to that target
///    (target membership for both Runner and the extension).
/// 4. Runner + extension: Signing & Capabilities → **Push Notifications**,
///    App Group (same as Payghaam NSE if you use one).
/// 5. Runner Info.plist: `NSSupportsLiveActivities` = `YES`.
///
/// Until the extension exists, local `Activity.request` still runs and tokens
/// still register with Payghaam — but the Lock Screen / Dynamic Island UI will
/// not render.
@available(iOS 16.1, *)
struct DeliveryLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DeliveryAttributes.self) { context in
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Order \(context.attributes.orderId)")
            .font(.headline)
          Text(context.state.stage.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.subheadline)
        }
        Spacer()
        Text("\(context.state.etaMinutes) min")
          .font(.title2.bold())
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text("Order \(context.attributes.orderId)")
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(context.state.etaMinutes)m")
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.stage)
        }
      } compactLeading: {
        Text("📦")
      } compactTrailing: {
        Text("\(context.state.etaMinutes)m")
      } minimal: {
        Text("📦")
      }
    }
  }
}
