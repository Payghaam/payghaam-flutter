import 'dart:async';

import 'package:flutter/services.dart';

/// Live Activities bridge — reuses [payghaam-ios] ActivityKit token plumbing.
///
/// Token registration stays in the native SDK (`PayghaamLiveActivities.observe`).
/// This Dart surface only:
/// * asks the plugin to `refreshAll()` (re-scan running activities)
/// * optionally listens for token-registration notifications from the iOS SDK
/// * invokes **host-implemented** local start/update/end channels (ActivityKit
///   needs a typed `ActivityAttributes`; the example app wires `DeliveryAttributes`)
///
/// Drive activities from your backend with a **REST** project key:
/// `POST/PATCH/DELETE /api/live-activities` — not the SDK key.
class PayghaamLiveActivities {
  PayghaamLiveActivities._();

  static const MethodChannel _channel =
      MethodChannel('payghaam/liveActivities');
  static const MethodChannel _local = MethodChannel(
    'payghaam/liveActivitiesLocal',
  );
  static const EventChannel _updateToken = EventChannel(
    'payghaam/liveActivityUpdateToken',
  );
  static const EventChannel _startToken = EventChannel(
    'payghaam/liveActivityStartToken',
  );

  static Stream<Map<String, dynamic>>? _updateTokenStream;
  static Stream<Map<String, dynamic>>? _startTokenStream;

  /// Re-scan every attributes type the host passed to
  /// `PayghaamLiveActivities.observe(...)` in AppDelegate.
  ///
  /// No-op on non-iOS or when the plugin is absent.
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Android / web / desktop — Live Activities are iOS-only.
    }
  }

  /// Emitted after payghaam-ios POSTs (or fails to POST) an update token.
  ///
  /// Map keys: `activityId` (String), `ok` (bool), optional `tokenPrefix` /
  /// `error` (String). Prefer this over iterating `pushTokenUpdates` in Swift —
  /// a second consumer can starve the SDK.
  static Stream<Map<String, dynamic>> get onUpdateTokenRegistered =>
      _updateTokenStream ??= _updateToken.receiveBroadcastStream().map(_asMap);

  /// Emitted after payghaam-ios registers the push-to-start token (iOS 17.2+).
  ///
  /// Map keys: `ok` (bool), optional `tokenPrefix` / `error` (String).
  static Stream<Map<String, dynamic>> get onStartTokenRegistered =>
      _startTokenStream ??= _startToken.receiveBroadcastStream().map(_asMap);

  /// Start a local Live Activity via the host AppDelegate method channel.
  ///
  /// Requires the example (or your app) to implement
  /// `payghaam/liveActivitiesLocal` with `DeliveryAttributes` (or your own type).
  /// Returns the ActivityKit id, or `null` if unsupported / unimplemented.
  static Future<String?> startActivity({
    required String orderId,
    String stage = 'picked_up',
    int etaMinutes = 30,
  }) async {
    try {
      return await _local.invokeMethod<String>('startActivity', {
        'orderId': orderId,
        'stage': stage,
        'etaMinutes': etaMinutes,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Update a running local activity by [activityId] (ActivityKit id) or
  /// [orderId] (matches `PayghaamLiveActivityIdentifiable` handle `order-<id>`).
  static Future<bool> updateActivity({
    String? activityId,
    String? orderId,
    required String stage,
    required int etaMinutes,
  }) async {
    try {
      final ok = await _local.invokeMethod<bool>('updateActivity', {
        if (activityId != null) 'activityId': activityId,
        if (orderId != null) 'orderId': orderId,
        'stage': stage,
        'etaMinutes': etaMinutes,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// End a running local activity (see [updateActivity] for addressing).
  static Future<bool> endActivity({
    String? activityId,
    String? orderId,
    String stage = 'delivered',
    int etaMinutes = 0,
  }) async {
    try {
      final ok = await _local.invokeMethod<bool>('endActivity', {
        if (activityId != null) 'activityId': activityId,
        if (orderId != null) 'orderId': orderId,
        'stage': stage,
        'etaMinutes': etaMinutes,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }
}
