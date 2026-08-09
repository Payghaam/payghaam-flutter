import 'package:flutter/services.dart' show MissingPluginException;

import 'api_bridge.dart';
import 'api_client.dart';
import 'config.dart';

/// User-scoped operations: tags and additional channel subscriptions.
/// Obtained via `Payghaam.instance.user`.
class UserManager {
  final ApiBridge _bridge;
  // HTTP fallback, used only where there's no native SDK to delegate to
  // (web/desktop — see api_bridge.dart).
  final ApiClient _api;
  final String? Function() _externalId;
  final bool Function() _canSend;

  UserManager(this._bridge, this._api, this._externalId, this._canSend);

  String _requireExternalId() {
    final id = _externalId();
    if (id == null) {
      throw StateError(
        'Call Payghaam.login(externalId) before setting user data.',
      );
    }
    return id;
  }

  /// Set a single tag (key-value pair) on the current user for audience
  /// segmentation. Shorthand for `addTags({key: value})`.
  Future<void> addTag(String key, Object value) => addTags({key: value});

  /// Set multiple tags (key-value pairs) on the current user for audience
  /// segmentation. The backend merges these with any existing tags.
  Future<void> addTags(Map<String, Object?> tags) async {
    if (!_canSend()) return;
    final externalId = _requireExternalId();
    try {
      await _bridge.updateTags(tags);
    } on MissingPluginException {
      await _api.updateTags(externalId, tags);
    }
  }

  /// Remove tags by setting them to null (backend merges).
  Future<void> removeTag(String key) => addTags({key: null});

  /// Add an email subscription for the current user.
  Future<void> addEmail(String email) async {
    if (!_canSend()) return;
    final externalId = _requireExternalId();
    try {
      await _bridge.addSubscription(
        type: SubscriptionType.email.wire,
        token: email,
      );
    } on MissingPluginException {
      await _api.addSubscription(
        externalId: externalId,
        type: SubscriptionType.email,
        token: email,
      );
    }
  }

  /// Add an SMS subscription for the current user.
  Future<void> addSms(String phoneE164) async {
    if (!_canSend()) return;
    final externalId = _requireExternalId();
    try {
      await _bridge.addSubscription(
        type: SubscriptionType.sms.wire,
        token: phoneE164,
      );
    } on MissingPluginException {
      await _api.addSubscription(
        externalId: externalId,
        type: SubscriptionType.sms,
        token: phoneE164,
      );
    }
  }
}
