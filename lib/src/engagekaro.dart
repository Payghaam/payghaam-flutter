import 'dart:async';

import 'api_client.dart';
import 'config.dart';
import 'native_push_provider.dart';
import 'notifications.dart';
import 'storage.dart';
import 'user_manager.dart';

/// Entry point for the EngageKaro Flutter SDK.
///
/// ```dart
/// await EngageKaro.instance.initialize(EngageKaroConfig(
///   appId: 'project_id', apiKey: 'ek_client_...', baseUrl: 'https://api.host',
/// ));
/// await EngageKaro.instance.login('app-user-id');
/// await EngageKaro.instance.user.addTag('plan', 'pro');
/// await EngageKaro.instance.trackEvent('purchase', {'sku': 'x'});
/// ```
class EngageKaro {
  EngageKaro._();
  static final EngageKaro instance = EngageKaro._();

  late EngageKaroConfig _config;
  late ApiClient _api;
  late UserManager _user;
  final Storage _storage = Storage();
  // Defaults to native push (iOS APNs / Android FCM). Pass a different
  // PushProvider to initialize() to override (e.g. NoopPushProvider for
  // comms-only usage with no push).
  PushProvider _push = EngageKaroPushProvider();

  bool _initialized = false;
  bool _consentGiven = false;
  String? _externalId;
  String? _pendingPushToken; // captured before login completes
  final List<StreamSubscription<dynamic>> _subs = [];

  UserManager get user => _user;

  /// Whether network calls are currently allowed (respects consent gating).
  bool get _canSend => _initialized && (!_config.requireConsent || _consentGiven);

  /// Initialize the SDK. Optionally pass a [PushProvider] (e.g. a
  /// firebase_messaging-backed implementation) to enable push registration.
  Future<void> initialize(EngageKaroConfig config, {PushProvider? push}) async {
    _config = config;
    _api = ApiClient(config);
    _user = UserManager(_api, () => _externalId, () => _canSend);
    if (push != null) _push = push;

    _externalId = await _storage.getExternalId();
    _consentGiven = config.requireConsent ? await _storage.getConsent() : true;
    _initialized = true;

    _wirePushListeners();

    // Report a cold-start open (app launched by tapping a notification).
    final initial = await _push.getInitialNotification();
    if (initial != null) _reportReceiptFromData(initial, 'opened');
  }

  void _wirePushListeners() {
    // onError guards keep the SDK usable on platforms without the native plugin
    // (e.g. web/desktop/tests) where the event channels aren't available.
    _subs.add(_push.onTokenRefresh.listen(
      (token) => _registerPushToken(token),
      onError: (_) {},
    ));
    _subs.add(_push.onNotificationOpened.listen(
      (data) => _reportReceiptFromData(data, 'opened'),
      onError: (_) {},
    ));
    _subs.add(_push.onForegroundMessage.listen(
      (data) => _reportReceiptFromData(data, 'delivered'),
      onError: (_) {},
    ));
  }

  void _reportReceiptFromData(Map<String, dynamic> data, String event) {
    final messageId = data['ek_message_id'];
    if (messageId is String && messageId.isNotEmpty) {
      reportPushReceipt(messageId, event, properties: data);
    }
  }

  /// Report a push delivery/engagement receipt (delivered | opened | clicked).
  Future<void> reportPushReceipt(
    String messageId,
    String event, {
    Map<String, dynamic>? properties,
  }) async {
    if (!_canSend) return;
    await _api.reportReceipt(
      messageId: messageId,
      event: event,
      externalId: _externalId,
      properties: properties,
    );
  }

  /// Identify the current user by your backend's user id (External ID).
  ///
  /// If the project has Identity Verification enabled, pass [identityHash] =
  /// HMAC-SHA256(externalId) computed **on your server** with the project secret
  /// (never ship the secret in the app).
  Future<void> login(String externalId, {String? identityHash}) async {
    _externalId = externalId;
    _api.identityHash = identityHash;
    await _storage.setExternalId(externalId);
    if (!_canSend) return;
    await _api.identify(externalId: externalId);
    // Flush any push token captured before the user was identified.
    final token = _pendingPushToken ?? await _push.getToken();
    if (token != null) await _registerPushToken(token);
  }

  /// Clear the current user identity on this device.
  Future<void> logout() async {
    _externalId = null;
    _api.identityHash = null;
    await _storage.setExternalId(null);
  }

  /// Track a custom event (drives journeys + analytics).
  Future<void> trackEvent(String name, [Map<String, dynamic>? properties]) async {
    if (!_canSend) return;
    await _api.track(name: name, externalId: _externalId, properties: properties);
  }

  /// Prompt for OS notification permission (delegates to the PushProvider) and
  /// register the resulting token if granted.
  Future<bool> requestPushPermission() async {
    final granted = await _push.requestPermission();
    if (granted) {
      final token = await _push.getToken();
      if (token != null) await _registerPushToken(token);
    }
    return granted;
  }

  /// Manually register a device push token (call this if you manage tokens
  /// yourself instead of via a PushProvider).
  Future<void> registerPushToken(String token, SubscriptionType platform) async {
    await _registerPushToken(token, platform: platform);
  }

  Future<void> _registerPushToken(String token, {SubscriptionType? platform}) async {
    if (!_canSend) return;
    if (_externalId == null) {
      _pendingPushToken = token; // register once the user logs in
      return;
    }
    await _api.addSubscription(
      externalId: _externalId!,
      type: platform ?? _push.subscriptionType,
      token: token,
    );
    _pendingPushToken = null;
  }

  // ── Consent gating ──────────────────────────────────────────────────────────
  void setConsentRequired(bool required) {
    _config = EngageKaroConfig(
      appId: _config.appId,
      apiKey: _config.apiKey,
      baseUrl: _config.baseUrl,
      requireConsent: required,
      timeout: _config.timeout,
    );
  }

  Future<void> setConsentGiven(bool given) async {
    _consentGiven = given;
    await _storage.setConsent(given);
    if (given) {
      // re-run identification + token registration now that we're allowed.
      final id = _externalId;
      if (id != null) await login(id);
    }
  }

  /// Tear down listeners and the HTTP client.
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _api.close();
  }
}
