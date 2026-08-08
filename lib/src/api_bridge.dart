import 'package:flutter/services.dart';

import 'api_client.dart';

/// Native-SDK pass-through for the comms API (identify/track/tags/receipts).
///
/// On iOS/Android this proxies through the canonical native SDK's `ApiClient`
/// + offline queue (see sdk-native-wrapper-design.md §4.5) instead of Dart
/// making its own HTTP calls — the native SDK is the single implementation of
/// this logic on those two platforms. On web/desktop there is no native SDK to
/// delegate to (the bundled plugin only registers a stub method-channel
/// handler there — see method_handler.dart), so every method here throws
/// [MissingPluginException] on those platforms; callers fall back to
/// [ApiClient] (the `package:http`-based implementation) in that case. That
/// fallback is the one piece of intentional duplication left after the
/// native-wrapper refactor — everywhere a native SDK exists, this bridge is
/// the only path.
class ApiBridge {
  static const MethodChannel _methods = MethodChannel('payghaam/methods');

  /// Mirror native's `config`/`externalId`/`identityHash` state. Call once in
  /// `initialize()` (externalId omitted) and again in `login()` (externalId
  /// set) — safe to call repeatedly, never clears an already-set externalId.
  Future<void> sync({
    required String apiKey,
    required String baseUrl,
    String? externalId,
    String? identityHash,
  }) async {
    try {
      await _methods.invokeMethod<void>('apiSync', {
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'externalId': externalId,
        'identityHash': identityHash,
      });
    } on MissingPluginException {
      // No native plugin (web/desktop) — nothing to mirror; ApiClient carries
      // its own externalId/identityHash state directly.
    }
  }

  /// Clears native's mirrored identity. Call from `logout()`.
  Future<void> clearIdentity() async {
    try {
      await _methods.invokeMethod<void>('apiClearIdentity');
    } on MissingPluginException {
      // no-op — see [sync].
    }
  }

  Future<void> identify({Map<String, dynamic>? deviceContext}) =>
      _invoke('apiIdentify', {'deviceContext': deviceContext});

  Future<void> addSubscription({
    required String type,
    required String token,
    String? deviceModel,
    String? deviceOs,
    String? appVersion,
  }) =>
      _invoke('apiAddSubscription', {
        'type': type,
        'token': token,
        'deviceModel': deviceModel,
        'deviceOs': deviceOs,
        'appVersion': appVersion,
      });

  Future<void> updateTags(Map<String, dynamic> tags) =>
      _invoke('apiUpdateTags', {'tags': tags});

  Future<void> track(String name, [Map<String, dynamic>? properties]) =>
      _invoke('apiTrack', {'name': name, 'properties': properties});

  Future<void> reportReceipt(
    String messageId,
    String event, [
    Map<String, dynamic>? properties,
  ]) =>
      _invoke('apiReportReceipt', {
        'messageId': messageId,
        'event': event,
        'properties': properties,
      });

  Future<void> flushQueue() => _invoke('apiFlushQueue', null);

  /// Rethrows [MissingPluginException] (the "no native SDK here, fall back"
  /// signal) as-is; converts the native SDK's `payghaam_api_error` into an
  /// [PayghaamApiException] so callers can handle both bridge and HTTP paths
  /// identically. `details` carries the status code the native side attached.
  Future<void> _invoke(String method, Map<String, dynamic>? args) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      if (e.code == 'payghaam_api_error') {
        final statusCode = e.details is int ? e.details as int : 0;
        throw PayghaamApiException(statusCode, e.message ?? '');
      }
      rethrow;
    }
  }
}
