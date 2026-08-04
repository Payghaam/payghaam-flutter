// EngageKaro Notification Service Extension
//
// Copy this file into your `OneSignalNotificationServiceExtension`-style NSE
// target (see IOS_SETUP.md). It reports a `delivered` receipt to EngageKaro even
// when the app is terminated, and (optionally) attaches a rich image.
//
// Requirements:
//  - The NSE target and the app target share an App Group.
//  - Both targets have an Info.plist string key `EngageKaroAppGroup` set to that
//    App Group id (e.g. `group.com.yourcompany.app.engagekaro`).
//  - The main app calls `ApnsPushProvider.shareConfigForExtension(...)` after
//    login so apiBase/apiKey/externalId are available here.
//  - The NSE target depends on the canonical `EngageKaro` pod/package
//    (sdks/ios) — add `target 'YourNSETarget' do pod 'EngageKaro', :path =>
//    '...' end` to your Podfile, or add the EngageKaro Swift package as a
//    dependency of the target in Xcode. See sdk-native-wrapper-design.md.

import EngageKaro
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttempt: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    self.bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
    let userInfo = request.content.userInfo

    if let messageId = userInfo["ek_message_id"] as? String {
      reportDelivered(messageId: messageId)
    }

    // Optional rich media: attach an image if the payload carries `ek_image`.
    if let urlString = userInfo["ek_image"] as? String,
       let url = URL(string: urlString),
       let best = bestAttempt {
      EngageKaroReceipts.downloadAttachment(url: url) { attachment in
        if let a = attachment { best.attachments = [a] }
        contentHandler(best)
      }
      return
    }

    if let best = bestAttempt { contentHandler(best) }
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let best = bestAttempt {
      handler(best)
    }
  }

  // MARK: - Receipt

  private func reportDelivered(messageId: String) {
    // Flutter's `engagekaro.*` App Group key scheme — see
    // engagekaro_flutter's saveSharedConfig, which writes these dotted keys
    // (distinct from the canonical SDK's own `ek_*` scheme used by native and
    // React Native apps; left as-is to avoid breaking already-integrated apps'
    // NSE templates — see sdk-native-wrapper-design.md).
    guard
      let appGroup = Bundle.main.object(forInfoDictionaryKey: "EngageKaroAppGroup") as? String,
      let defaults = UserDefaults(suiteName: appGroup),
      let apiBase = defaults.string(forKey: "engagekaro.apiBase"),
      let apiKey = defaults.string(forKey: "engagekaro.apiKey")
    else { return }

    EngageKaroReceipts.reportDeliveredBlocking(
      apiBase: apiBase,
      apiKey: apiKey,
      externalId: defaults.string(forKey: "engagekaro.externalId"),
      identityHash: defaults.string(forKey: "engagekaro.identityHash"),
      messageId: messageId
    )
  }
}
