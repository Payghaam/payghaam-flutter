import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'offline_queue.dart';

/// Thin REST client over the Payghaam `/api/sdk/*` endpoints.
/// Every call is authenticated with the project's SDK key.
class ApiClient {
  final PayghaamConfig config;
  final http.Client _http;

  /// HMAC-SHA256(externalId) for Identity Verification. Set via [Payghaam.login]
  /// when the project requires it; sent on every call as a header.
  String? identityHash;

  ApiClient(this.config, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${config.apiKey}',
        'x-api-key': config.apiKey,
        if (identityHash != null) 'x-payghaam-identity-hash': identityHash!,
      };

  Uri _uri(String path) => Uri.parse('${config.apiRoot}$path');

  /// Installed by Payghaam on init; parks retryable failures offline.
  OfflineQueue? queue;

  // Fire-and-forget path: send now, or park in the offline queue on a
  // retryable failure so offline activity isn't lost.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return _sendOrQueue('POST', path, body);
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) {
    return _sendOrQueue('PUT', path, body);
  }

  Future<Map<String, dynamic>> _sendOrQueue(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await rawRequest(method, path, body);
      unawaited(queue?.flush());
      return res;
    } catch (e) {
      final q = queue;
      if (q != null && OfflineQueue.isRetryable(e)) {
        await q.enqueue(method, path, body);
        return <String, dynamic>{};
      }
      rethrow;
    }
  }

  /// Direct request without queueing — used by OfflineQueue's drain.
  Future<Map<String, dynamic>> rawRequest(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await (method == 'PUT'
            ? _http.put(
                _uri(path),
                headers: _headers,
                body: jsonEncode(body),
              )
            : _http.post(
                _uri(path),
                headers: _headers,
                body: jsonEncode(body),
              ))
        .timeout(config.timeout);
    return _parse(res);
  }

  Map<String, dynamic> _parse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    }
    throw PayghaamApiException(res.statusCode, res.body);
  }

  /// Create/identify a user. Returns the subscriber payload.
  Future<Map<String, dynamic>> identify({
    String? externalId,
    Map<String, dynamic>? tags,
    List<Map<String, dynamic>>? subscriptions,
    Map<String, dynamic>? deviceContext,
  }) {
    return _post('/users', {
      if (externalId != null) 'externalId': externalId,
      if (tags != null) 'tags': tags,
      if (subscriptions != null) 'subscriptions': subscriptions,
      if (deviceContext != null) ...deviceContext,
    });
  }

  /// Register a channel subscription (push token / email / phone) for a user.
  Future<Map<String, dynamic>> addSubscription({
    required String externalId,
    required SubscriptionType type,
    required String token,
    String? deviceModel,
    String? deviceOs,
    String? appVersion,
    String? sdk,
  }) {
    return _post('/subscriptions', {
      'externalId': externalId,
      'type': type.wire,
      'token': token,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (deviceOs != null) 'deviceOs': deviceOs,
      if (appVersion != null) 'appVersion': appVersion,
      if (sdk != null) 'sdk': sdk,
    });
  }

  Future<Map<String, dynamic>> updateTags(
    String externalId,
    Map<String, dynamic> tags,
  ) {
    return _put('/tags', {
      'externalId': externalId,
      'tags': tags,
    });
  }

  Future<Map<String, dynamic>> track({
    required String name,
    String? externalId,
    Map<String, dynamic>? properties,
    String? idempotencyKey,
    Map<String, dynamic>? deviceContext,
  }) {
    return _post('/events', {
      'name': name,
      if (externalId != null) 'externalId': externalId,
      if (properties != null) 'properties': properties,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      if (deviceContext != null) ...deviceContext,
    });
  }

  Future<Map<String, dynamic>> optOut(SubscriptionType type, String token) {
    return _post('/opt-out', {'type': type.wire, 'token': token});
  }

  /// Report a delivery/engagement receipt (delivered | opened | clicked).
  Future<Map<String, dynamic>> reportReceipt({
    required String messageId,
    required String event,
    String? externalId,
    Map<String, dynamic>? properties,
  }) {
    return _post('/receipts', {
      'messageId': messageId,
      'event': event,
      if (externalId != null) 'externalId': externalId,
      if (properties != null) 'properties': properties,
    });
  }

  void close() => _http.close();
}

class PayghaamApiException implements Exception {
  final int statusCode;
  final String body;
  PayghaamApiException(this.statusCode, this.body);

  @override
  String toString() => 'PayghaamApiException($statusCode): $body';
}
