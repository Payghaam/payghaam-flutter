import ActivityKit
import Foundation
import Payghaam

/// Sample Live Activity attributes for the Payghaam Flutter example.
///
/// Share this file with your Widget Extension target (same type name + fields
/// as the server's `attributes` / `contentState` JSON).
@available(iOS 16.1, *)
public struct DeliveryAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var stage: String
    public var etaMinutes: Int

    public init(stage: String, etaMinutes: Int) {
      self.stage = stage
      self.etaMinutes = etaMinutes
    }
  }

  public var orderId: String

  public init(orderId: String) {
    self.orderId = orderId
  }
}

@available(iOS 16.1, *)
extension DeliveryAttributes: PayghaamLiveActivityIdentifiable {
  public var payghaamActivityId: String { "order-\(orderId)" }
}
