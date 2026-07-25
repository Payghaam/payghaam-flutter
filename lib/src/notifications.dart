import 'config.dart';

/// Strategy interface for the native push layer. Implement this with
/// `firebase_messaging` (recommended) or a native plugin, and pass it to
/// [EngageKaro.initialize]. Keeping it abstract makes the comms core
/// independent of any push provider.
abstract class PushProvider {
  /// Ask the OS for notification permission. Returns whether granted.
  Future<bool> requestPermission();

  /// The current device push token (FCM token / APNs token), or null.
  Future<String?> getToken();

  /// The platform's subscription type for this device.
  SubscriptionType get subscriptionType;

  /// Emits a new token whenever it is refreshed by the OS.
  Stream<String> get onTokenRefresh;

  /// Emits when a notification is tapped (payload data), for `push_opened`.
  Stream<Map<String, dynamic>> get onNotificationOpened;

  /// Emits when a notification arrives while the app is in the foreground,
  /// for reporting `delivered` receipts.
  Stream<Map<String, dynamic>> get onForegroundMessage;

  /// Returns the notification that cold-launched the app (tapped from terminated
  /// state), or null. Used to report the initial `opened` receipt on startup.
  Future<Map<String, dynamic>?> getInitialNotification();

  /// Hands [url] to the platform (Android `ACTION_VIEW` / iOS `openURL`).
  /// Used for the deep-link fallback when the app listens to no tap stream.
  /// Returns whether anything could handle it.
  Future<bool> openDeepLink(String url);
}

/// Default no-op provider used when the app hasn't supplied one yet. Lets the
/// comms core run (identify/tags/events) without push wired up.
class NoopPushProvider implements PushProvider {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  SubscriptionType get subscriptionType => SubscriptionType.androidPush;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Stream<Map<String, dynamic>> get onNotificationOpened =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async => null;

  @override
  Future<bool> openDeepLink(String url) async => false;
}
