import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import 'config.dart';
import 'notifications.dart';

/// The push provider — native on both platforms: **iOS → APNs** (no Firebase),
/// **Android → FCM**. Use the same instance everywhere; there is no platform
/// branching. The native layers expose identical channels.
class PayghaamPushProvider implements PushProvider {
  static const MethodChannel _methods = MethodChannel('payghaam/methods');
  static const EventChannel _onToken = EventChannel('payghaam/onToken');
  static const EventChannel _onOpened = EventChannel('payghaam/onOpened');
  static const EventChannel _onForeground = EventChannel(
    'payghaam/onForeground',
  );

  /// The subscription channel for the current platform: `iosPush` on iOS,
  /// `androidPush` on Android, and `webPush` everywhere else.
  @override
  SubscriptionType get subscriptionType {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return SubscriptionType.iosPush;
      case TargetPlatform.android:
        return SubscriptionType.androidPush;
      default:
        return SubscriptionType.webPush;
    }
  }

  /// Prompt the OS for notification permission. Returns whether permission
  /// was granted, or `false` if the native plugin isn't available.
  @override
  Future<bool> requestPermission() async {
    try {
      return (await _methods.invokeMethod<bool>('requestPermission')) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Register for remote notifications and fetch the current device push
  /// token, or `null` if the native plugin isn't available.
  @override
  Future<String?> getToken() async {
    try {
      await _methods.invokeMethod<void>('registerForRemoteNotifications');
      return _methods.invokeMethod<String>('getToken');
    } on MissingPluginException {
      return null;
    }
  }

  // Each of these streams is created ONCE and shared by every subscriber.
  //
  // `EventChannel.receiveBroadcastStream()` builds a fresh StreamController per
  // call and sends its own `listen` to the platform. The native side keeps a
  // single sink per channel, so the last subscriber silently replaced the
  // previous one: when a host app did
  //
  //     Payghaam.instance.initialize(config, push: push);  // SDK subscribes
  //     push.onNotificationOpened.listen(...);               // app subscribes
  //
  // the app's listener orphaned the SDK's, and the SDK stopped reporting `opened`
  // receipts entirely — while `delivered` kept working, because Android posts that
  // one natively from the FCM service without going through Dart.
  //
  // Caching keeps one platform subscription and lets both listeners receive.
  //
  // Static, not per-instance: the EventChannels themselves are `static const`, so
  // two provider instances would collide on the same native sink. Sharing the
  // stream makes that impossible rather than merely unlikely.
  static Stream<String>? _tokenStream;
  static Stream<Map<String, dynamic>>? _openedStream;
  static Stream<Map<String, dynamic>>? _foregroundStream;

  @override
  Stream<String> get onTokenRefresh => _tokenStream ??= _onToken
      .receiveBroadcastStream()
      .map((e) => e as String);

  @override
  Stream<Map<String, dynamic>> get onNotificationOpened =>
      _openedStream ??= _onOpened.receiveBroadcastStream().map(_asMap);

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      _foregroundStream ??= _onForeground.receiveBroadcastStream().map(_asMap);

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async {
    try {
      final res = await _methods.invokeMethod<dynamic>(
        'getInitialNotification',
      );
      return res == null ? null : _asMap(res);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openDeepLink(String url) async {
    try {
      return (await _methods.invokeMethod<bool>('openUrl', {'url': url})) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Map<String, dynamic> _asMap(dynamic e) =>
      (e as Map).map((k, v) => MapEntry(k.toString(), v));

  /// Persist config natively so the iOS Notification Service Extension and the
  /// Android FCM service can report `delivered` receipts while terminated.
  /// On iOS pass [appGroup]; Android ignores it. Call after `login()`.
  Future<void> shareConfig({
    String? appGroup,
    required String apiBase,
    required String apiKey,
    String? externalId,
    String? identityHash,
  }) async {
    try {
      await _methods.invokeMethod<void>('setSharedConfig', {
        'appGroup': appGroup,
        'apiBase': apiBase,
        'apiKey': apiKey,
        'externalId': externalId,
        'identityHash': identityHash,
      });
    } on MissingPluginException {
      // unsupported platform — ignore
    }
  }
}
