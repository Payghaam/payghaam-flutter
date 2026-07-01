/// Configuration passed to [EngageKaro.initialize].
class EngageKaroConfig {
  /// EngageKaro project id (your app's id on the platform).
  final String appId;

  /// SDK-type API key created in the dashboard (client-scoped, NOT the REST key).
  final String apiKey;

  /// Base URL of your EngageKaro API, e.g. `https://api.yourhost.com`.
  final String baseUrl;

  /// When true, no network calls are made until [EngageKaro.setConsentGiven]
  /// is called with `true`.
  final bool requireConsent;

  /// Request timeout for API calls.
  final Duration timeout;

  /// When true, errors are printed to the console (useful during integration).
  final bool debug;

  /// Optional hook for background failures (identify, push registration, etc.).
  final void Function(Object error, String context)? onError;

  const EngageKaroConfig({
    required this.appId,
    required this.apiKey,
    required this.baseUrl,
    this.requireConsent = false,
    this.timeout = const Duration(seconds: 15),
    this.debug = false,
    this.onError,
  });

  /// Normalized base (no trailing slash).
  String get apiRoot {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$b/api/sdk';
  }
}

/// Channel endpoint types, mirroring the platform's `SubscriptionType`.
enum SubscriptionType {
  androidPush,
  iosPush,
  webPush,
  email,
  sms;

  /// Wire value expected by the backend.
  String get wire {
    switch (this) {
      case SubscriptionType.androidPush:
        return 'ANDROID_PUSH';
      case SubscriptionType.iosPush:
        return 'IOS_PUSH';
      case SubscriptionType.webPush:
        return 'WEB_PUSH';
      case SubscriptionType.email:
        return 'EMAIL';
      case SubscriptionType.sms:
        return 'SMS';
    }
  }
}
