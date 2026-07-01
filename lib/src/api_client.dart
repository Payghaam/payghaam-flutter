import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';

/// Thin REST client over the EngageKaro `/api/sdk/*` endpoints.
/// Every call is authenticated with the project's SDK key.
class ApiClient {
  final EngageKaroConfig config;
  final http.Client _http;

  /// HMAC-SHA256(externalId) for Identity Verification. Set via [EngageKaro.login]
  /// when the project requires it; sent on every call as a header.
  String? identityHash;

  ApiClient(this.config, {http.Client? client})
      : _http = client ?? http.Client();

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${config.apiKey}',
        'x-api-key': config.apiKey,
        if (identityHash != null) 'x-engagekaro-identity-hash': identityHash!,
      };

  Uri _uri(String path) => Uri.parse('${config.apiRoot}$path');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final res = await _http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(config.timeout);
    return _parse(res);
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final res = await _http
        .put(_uri(path), headers: _headers, body: jsonEncode(body))
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
    throw EngageKaroApiException(res.statusCode, res.body);
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
    return _post('/users/$externalId/subscriptions', {
      'type': type.wire,
      'token': token,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (deviceOs != null) 'deviceOs': deviceOs,
      if (appVersion != null) 'appVersion': appVersion,
      if (sdk != null) 'sdk': sdk,
    });
  }

  Future<Map<String, dynamic>> updateTags(
      String externalId, Map<String, dynamic> tags) {
    return _put('/users/$externalId/tags', {'tags': tags});
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

class EngageKaroApiException implements Exception {
  final int statusCode;
  final String body;
  EngageKaroApiException(this.statusCode, this.body);

  @override
  String toString() => 'EngageKaroApiException($statusCode): $body';
}
