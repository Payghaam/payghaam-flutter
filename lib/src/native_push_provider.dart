import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

import 'config.dart';
import 'notifications.dart';

/// The push provider — native on both platforms: **iOS → APNs** (no Firebase),
/// **Android → FCM**. Use the same instance everywhere; there is no platform
/// branching. The native layers expose identical channels.
class EngageKaroPushProvider implements PushProvider {
  static const MethodChannel _methods = MethodChannel('engagekaro/methods');
  static const EventChannel _onToken = EventChannel('engagekaro/onToken');
  static const EventChannel _onOpened = EventChannel('engagekaro/onOpened');
  static const EventChannel _onForeground = EventChannel('engagekaro/onForeground');

  @override
  SubscriptionType get subscriptionType =>
      Platform.isIOS ? SubscriptionType.iosPush : SubscriptionType.androidPush;

  @override
  Future<bool> requestPermission() async {
    try {
      return (await _methods.invokeMethod<bool>('requestPermission')) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      await _methods.invokeMethod<void>('registerForRemoteNotifications');
      return _methods.invokeMethod<String>('getToken');
    } on MissingPluginException {
      return null;
    }
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
    try {
      final res = await _methods.invokeMethod<dynamic>('getInitialNotification');
      return res == null ? null : _asMap(res);
    } catch (_) {
      return null;
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
