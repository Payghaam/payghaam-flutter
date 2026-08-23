import Flutter
import Payghaam
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Live Activities: observe your ActivityAttributes once at launch (before
    // Dart login). The Flutter plugin forwards push-wake refresh; it does not
    // call observe() for you — ActivityKit needs a concrete type.
    if #available(iOS 16.1, *) {
      PayghaamLiveActivities.observe(DeliveryAttributes.self)
    }

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if #available(iOS 16.1, *),
       let controller = window?.rootViewController as? FlutterViewController {
      LiveActivitiesLocalChannel.register(messenger: controller.binaryMessenger)
    }

    return launched
  }
}
