import 'dart:async';
import 'package:flutter/services.dart';

import 'config.dart';
import 'notifications.dart';

/// iOS [PushProvider] backed by the native APNs plugin (no Firebase).
/// Use on iOS; use a firebase_messaging-backed provider on Android.
class ApnsPushProvider implements PushProvider {
  static const MethodChannel _methods = MethodChannel('engagekaro/methods');
  static const EventChannel _onToken = EventChannel('engagekaro/onToken');
  static const EventChannel _onOpened = EventChannel('engagekaro/onOpened');
  static const EventChannel _onForeground = EventChannel('engagekaro/onForeground');

  @override
  SubscriptionType get subscriptionType => SubscriptionType.iosPush;

  @override
  Future<bool> requestPermission() async {
    final granted = await _methods.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  @override
  Future<String?> getToken() async {
    await _methods.invokeMethod<void>('registerForRemoteNotifications');
    return _methods.invokeMethod<String>('getToken');
  }

  @override
  Stream<String> get onTokenRefresh =>
      _onToken.receiveBroadcastStream().map((e) => e as String);

  @override
  Stream<Map<String, dynamic>> get onNotificationOpened =>
      _onOpened.receiveBroadcastStream().map(_asMap);

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage =>
      _onForeground.receiveBroadcastStream().map(_asMap);

  @override
  Future<Map<String, dynamic>?> getInitialNotification() async {
    final res = await _methods.invokeMethod<dynamic>('getInitialNotification');
    return res == null ? null : _asMap(res);
  }

  Map<String, dynamic> _asMap(dynamic e) =>
      (e as Map).map((k, v) => MapEntry(k.toString(), v));

  /// Persist API config into the App Group so the Notification Service Extension
  /// can report `delivered` receipts while the app is terminated. Call after
  /// `login()` so the External ID is available to the extension.
  Future<void> shareConfigForExtension({
    required String appGroup,
    required String apiBase,
    required String apiKey,
    String? externalId,
  }) async {
    await _methods.invokeMethod<void>('setSharedConfig', {
      'appGroup': appGroup,
      'apiBase': apiBase,
      'apiKey': apiKey,
      'externalId': externalId,
    });
  }
}
