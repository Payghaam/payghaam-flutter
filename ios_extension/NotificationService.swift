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
      downloadAttachment(url: url) { attachment in
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
    guard
      let appGroup = Bundle.main.object(forInfoDictionaryKey: "EngageKaroAppGroup") as? String,
      let defaults = UserDefaults(suiteName: appGroup),
      let apiBase = defaults.string(forKey: "engagekaro.apiBase"),
      let apiKey = defaults.string(forKey: "engagekaro.apiKey"),
      let url = URL(string: "\(apiBase)/api/sdk/receipts")
    else { return }

    let externalId = defaults.string(forKey: "engagekaro.externalId")
    var body: [String: Any] = ["messageId": messageId, "event": "delivered"]
    if let ext = externalId { body["externalId"] = ext }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    // NSE has a short lifetime; block briefly so the request goes out.
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in semaphore.signal() }.resume()
    _ = semaphore.wait(timeout: .now() + 5)
  }

  private func downloadAttachment(
    url: URL,
    completion: @escaping (UNNotificationAttachment?) -> Void
  ) {
    URLSession.shared.downloadTask(with: url) { location, _, _ in
      guard let location = location else { completion(nil); return }
      let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + (url.pathExtension.isEmpty ? ".jpg" : "." + url.pathExtension))
      do {
        try FileManager.default.moveItem(at: location, to: tmp)
        completion(try UNNotificationAttachment(identifier: "image", url: tmp))
      } catch {
        completion(nil)
      }
    }.resume()
  }
}
