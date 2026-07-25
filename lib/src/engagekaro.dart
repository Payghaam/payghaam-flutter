import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'config.dart';
import 'device_context.dart';
import 'native_push_provider.dart';
import 'notifications.dart';
import 'offline_queue.dart';
import 'storage.dart';
import 'user_manager.dart';

/// Entry point for the EngageKaro Flutter SDK.
class EngageKaro with WidgetsBindingObserver {
  EngageKaro._();

  /// Singleton SDK instance. Call [initialize] once at app startup.
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
  String? _pushPermission; // granted | denied | unknown
  bool _sessionCountedThisLaunch = false;
  final SessionTracker _sessions = SessionTracker();
  final List<StreamSubscription<dynamic>> _subs = [];
  Future<void>? _profileSyncFuture;
  Future<void>? _postLoginFuture;

  final StreamController<Map<String, dynamic>> _opened =
      StreamController<Map<String, dynamic>>.broadcast();

  /// How long a cold-launch tap waits for the app to subscribe to
  /// [onNotificationOpened] before the SDK decides nobody is listening and opens
  /// the deep link itself. A tap that launches the app necessarily arrives before
  /// `initialize()` returns, so without this window the fallback would always win
  /// the race against an app that does its own routing.
  static const Duration _openedHandlerGrace = Duration(milliseconds: 400);

  /// User-scoped helpers (tags, email, SMS). Requires [login] first.
  UserManager get user => _user;

  /// Emits the full push payload whenever the user taps a notification — your
  /// custom `data` keys plus EngageKaro's own `ek_*` keys.
  ///
  /// ```dart
  /// EngageKaro.instance.onNotificationOpened.listen((payload) {
  ///   final target = payload['targetId'];
  ///   if (target is String) navigator.pushNamed('/offers/$target');
  /// });
  /// ```
  /// With no subscriber, the SDK opens `ek_url` (the campaign's deep link)
  /// itself. Subscribing suppresses that — routing becomes yours, including the
  /// deep link, available as `payload['ek_url']`.
  Stream<Map<String, dynamic>> get onNotificationOpened => _opened.stream;

  /// True after [initialize] has completed its local setup (network pings may still be in flight).
  bool get isInitialized => _initialized;

  /// Whether network calls are currently allowed (respects consent gating).
  bool get _canSend =>
      _initialized && (!_config.requireConsent || _consentGiven);

  void _reportError(Object error, String context) {
    if (_config.debug) {
      // ignore: avoid_print
      print('[EngageKaro] $context: $error');
    }
    _config.onError?.call(error, context);
  }

  /// Initialize the SDK. Optionally pass a [PushProvider] (e.g. a
  /// firebase_messaging-backed implementation) to enable push registration.
  Future<void> initialize(EngageKaroConfig config, {PushProvider? push}) async {
    _config = config;
    _api = ApiClient(config);
    _api.queue = OfflineQueue(_api.rawRequest);
    _user = UserManager(_api, () => _externalId, () => _canSend);
    if (push != null) _push = push;

    _externalId = await _storage.getExternalId();
    _consentGiven = config.requireConsent ? await _storage.getConsent() : true;
    _initialized = true;

    _wirePushListeners();
    WidgetsBinding.instance.addObserver(this);

    try {
      final initial = await _push.getInitialNotification();
      // Not awaited: dispatch gives the app a grace window to subscribe to
      // onNotificationOpened, and initialize() must not block on that.
      if (initial != null) {
        unawaited(_dispatchOpened(initial, allowGrace: true));
      }
    } catch (e) {
      _reportError(e, 'getInitialNotification');
    }

    if (_externalId != null) {
      unawaited(_syncDeviceProfile(sessionStart: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onForeground());
    }
  }

  Future<void> _onForeground() async {
    // Drain anything queued while the device was offline.
    unawaited(_api.queue?.flush());
    if (!_canSend || _externalId == null) return;
    if (!_sessions.noteForegroundResume()) return;
    unawaited(_syncDeviceProfile(sessionStart: true));
  }

  /// One identify per call site; concurrent callers share a single in-flight request.
  Future<void> _syncDeviceProfile({bool sessionStart = false}) {
    final existing = _profileSyncFuture;
    if (existing != null) return existing;
    _profileSyncFuture =
        _doSyncDeviceProfile(sessionStart: sessionStart).whenComplete(() {
      _profileSyncFuture = null;
    });
    return _profileSyncFuture!;
  }

  Future<void> _doSyncDeviceProfile({bool sessionStart = false}) async {
    if (!_canSend || _externalId == null) return;
    try {
      final countSession = sessionStart && !_sessionCountedThisLaunch;
      if (countSession) _sessionCountedThisLaunch = true;
      final ctx = await DeviceContext.collect(
        sessionStart: countSession,
        pushPermission: _pushPermission,
      );
      await _api.identify(
        externalId: _externalId,
        deviceContext: ctx.toJson(),
      );
    } catch (e) {
      _reportError(e, 'syncDeviceProfile');
    }
  }

  void _wirePushListeners() {
    // onError guards keep the SDK usable on platforms without the native plugin
    // (e.g. web/desktop/tests) where the event channels aren't available.
    _subs.add(_push.onTokenRefresh.listen(
      (token) => _registerPushToken(token),
      onError: (e) => _reportError(e, 'onTokenRefresh'),
    ));
    _subs.add(_push.onNotificationOpened.listen(
      (data) => unawaited(_dispatchOpened(data)),
      onError: (e) => _reportError(e, 'onNotificationOpened'),
    ));
    _subs.add(_push.onForegroundMessage.listen(
      (data) => _reportReceiptFromData(data, 'delivered'),
      onError: (e) => _reportError(e, 'onForegroundMessage'),
    ));
  }

  /// Route a notification tap: always report the receipt, then hand the payload
  /// to the app if it is listening, else fall back to opening `ek_url`.
  Future<void> _dispatchOpened(
    Map<String, dynamic> data, {
    bool allowGrace = false,
  }) async {
    _reportReceiptFromData(data, 'opened');

    if (allowGrace && !_opened.hasListener) {
      await Future<void>.delayed(_openedHandlerGrace);
    }
    if (_opened.hasListener) {
      _opened.add(data);
      return;
    }

    final url = data['ek_url'];
    if (url is! String || url.trim().isEmpty) return;
    try {
      final opened = await _push.openDeepLink(url.trim());
      if (!opened) {
        // Silently doing nothing here is the single most confusing failure in the
        // whole tap path, so say exactly what's wrong: the platform found no app
        // willing to handle the scheme.
        _reportError(
          'Nothing on the device can open "$url". Register the scheme with the OS: '
          'on Android add an <intent-filter> with android.intent.action.VIEW, '
          'category BROWSABLE/DEFAULT and your <data android:scheme="..."/> to the '
          'launcher activity in AndroidManifest.xml; on iOS add a URL Type in '
          'Info.plist (CFBundleURLSchemes).',
          'openDeepLink',
        );
      }
    } catch (e) {
      _reportError(e, 'openDeepLink');
    }
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
    try {
      await _api.reportReceipt(
        messageId: messageId,
        event: event,
        externalId: _externalId,
        properties: properties,
      );
    } catch (e) {
      _reportError(e, 'reportPushReceipt');
    }
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

    // Network enrichment (push token + single identify with device context) runs in background.
    unawaited(_runPostLoginTasks());
  }

  /// Best-effort push registration and one identify — never blocks [login].
  Future<void> _runPostLoginTasks() {
    final existing = _postLoginFuture;
    if (existing != null) return existing;
    _postLoginFuture = _doPostLoginTasks().whenComplete(() {
      _postLoginFuture = null;
    });
    return _postLoginFuture!;
  }

  Future<void> _doPostLoginTasks() async {
    final token = _pendingPushToken ?? await _push.getToken();
    if (token != null) await _registerPushToken(token);
    await _syncDeviceProfile(sessionStart: true);
  }

  /// Clear the current user identity on this device.
  Future<void> logout() async {
    _externalId = null;
    _api.identityHash = null;
    await _storage.setExternalId(null);
  }

  /// Track a custom event (drives journeys + analytics).
  Future<void> trackEvent(String name,
      [Map<String, dynamic>? properties]) async {
    if (!_canSend) return;
    try {
      await _api.track(
          name: name, externalId: _externalId, properties: properties);
    } catch (e) {
      _reportError(e, 'trackEvent');
    }
  }

  /// Prompt for OS notification permission (delegates to the PushProvider) and
  /// register the resulting token if granted.
  Future<bool> requestPushPermission() async {
    final granted = await _push.requestPermission();
    _pushPermission = granted ? 'granted' : 'denied';
    if (granted) {
      unawaited(() async {
        final token = await _push.getToken();
        if (token != null) await _registerPushToken(token);
        await _syncDeviceProfile();
      }());
    } else if (_canSend && _externalId != null) {
      unawaited(_syncDeviceProfile());
    }
    return granted;
  }

  /// Manually register a device push token (call this if you manage tokens
  /// yourself instead of via a PushProvider).
  Future<void> registerPushToken(
      String token, SubscriptionType platform) async {
    await _registerPushToken(token, platform: platform);
  }

  Future<void> _registerPushToken(String token,
      {SubscriptionType? platform}) async {
    if (!_canSend) return;
    if (_externalId == null) {
      _pendingPushToken = token; // register once the user logs in
      return;
    }
    try {
      final ctx = await DeviceContext.collect(pushPermission: _pushPermission);
      await _api.addSubscription(
        externalId: _externalId!,
        type: platform ?? _push.subscriptionType,
        token: token,
        deviceModel: ctx.deviceModel,
        deviceOs: ctx.osVersion != null
            ? '${ctx.os ?? ''} ${ctx.osVersion}'.trim()
            : ctx.os,
        appVersion: ctx.appVersion,
        sdk: ctx.sdkVersion,
      );
      _pendingPushToken = null;
    } catch (e) {
      _reportError(e, 'registerPushToken');
    }
  }

  // ── Consent gating ──────────────────────────────────────────────────────────

  /// Updates whether consent is required before any network calls are made.
  void setConsentRequired(bool required) {
    _config = EngageKaroConfig(
      appId: _config.appId,
      apiKey: _config.apiKey,
      baseUrl: _config.baseUrl,
      requireConsent: required,
      timeout: _config.timeout,
      debug: _config.debug,
      onError: _config.onError,
    );
  }

  /// Records user consent. When [given] is true, identification and token
  /// registration are re-run if a user is already logged in.
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
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    unawaited(_opened.close());
    _api.close();
  }
}
