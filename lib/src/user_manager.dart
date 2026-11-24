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
  final String Function() _anonymousId;
  final String? Function() _language;
  final bool Function() _canSend;
  final Future<void> Function(String? lang)? _onLanguageChanged;

  UserManager(
    this._bridge,
    this._api,
    this._externalId,
    this._anonymousId,
    this._language,
    this._canSend, {
    Future<void> Function(String? lang)? onLanguageChanged,
  }) : _onLanguageChanged = onLanguageChanged;

  /// Set a single tag (key-value pair) on the current user for audience
  /// segmentation. Shorthand for `addTags({key: value})`.
  Future<void> addTag(String key, Object value) => addTags({key: value});

  /// Set multiple tags (key-value pairs) on the current user for audience
  /// segmentation. The backend merges these with any existing tags.
  Future<void> addTags(Map<String, Object?> tags) async {
    if (!_canSend()) return;
    try {
      await _bridge.updateTags(tags);
    } on MissingPluginException {
      await _api.updateTags(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        tags: tags,
      );
    }
  }

  /// Remove tags by setting them to null (backend merges).
  Future<void> removeTag(String key) => addTags({key: null});

  /// Add an email subscription for the current user.
  Future<void> addEmail(String email) async {
    if (!_canSend()) return;
    try {
      await _bridge.addSubscription(
        type: SubscriptionType.email.wire,
        token: email,
      );
    } on MissingPluginException {
      await _api.addSubscription(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        type: SubscriptionType.email,
        token: email,
      );
    }
  }

  /// Add an SMS subscription for the current user.
  Future<void> addSms(String phoneE164) async {
    if (!_canSend()) return;
    try {
      await _bridge.addSubscription(
        type: SubscriptionType.sms.wire,
        token: phoneE164,
      );
    } on MissingPluginException {
      await _api.addSubscription(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        type: SubscriptionType.sms,
        token: phoneE164,
      );
    }
  }

  /// Remove an email subscription for the current user.
  Future<void> removeEmail(String email) async {
    if (!_canSend()) return;
    try {
      await _bridge.removeSubscription(
        type: SubscriptionType.email.wire,
        token: email,
      );
    } on MissingPluginException {
      await _api.removeSubscription(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        type: SubscriptionType.email,
        token: email,
      );
    }
  }

  /// Remove an SMS subscription for the current user.
  Future<void> removeSms(String phoneE164) async {
    if (!_canSend()) return;
    try {
      await _bridge.removeSubscription(
        type: SubscriptionType.sms.wire,
        token: phoneE164,
      );
    } on MissingPluginException {
      await _api.removeSubscription(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        type: SubscriptionType.sms,
        token: phoneE164,
      );
    }
  }

  /// Set custom language override for this user.
  Future<void> setLanguage(String? language) async {
    if (!_canSend()) return;
    if (_onLanguageChanged != null) {
      await _onLanguageChanged!(language);
    }
    try {
      await _bridge.setLanguage(language);
    } on MissingPluginException {
      await _api.identify(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        language: language,
      );
    }
  }

  /// Add a custom alias label/value pair (e.g. loyalty_id, shopify_id).
  Future<void> addAlias(String label, String value) =>
      addAliases({label: value});

  /// Add multiple custom aliases (label to value map).
  Future<void> addAliases(Map<String, String> aliases) async {
    if (!_canSend()) return;
    try {
      await _bridge.addAliases(aliases);
    } on MissingPluginException {
      await _api.addAliases(
        externalId: _externalId(),
        anonymousId: _anonymousId(),
        aliases: aliases,
      );
    }
  }
}
