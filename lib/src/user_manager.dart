import 'api_client.dart';
import 'config.dart';

/// User-scoped operations: tags and additional channel subscriptions.
/// Obtained via `EngageKaro.instance.user`.
class UserManager {
  final ApiClient _api;
  final String? Function() _externalId;
  final bool Function() _canSend;

  UserManager(this._api, this._externalId, this._canSend);

  String _requireExternalId() {
    final id = _externalId();
    if (id == null) {
      throw StateError('Call EngageKaro.login(externalId) before setting user data.');
    }
    return id;
  }

  Future<void> addTag(String key, Object value) => addTags({key: value});

  Future<void> addTags(Map<String, Object> tags) async {
    if (!_canSend()) return;
    await _api.updateTags(_requireExternalId(), tags);
  }

  /// Remove tags by setting them to null (backend merges).
  Future<void> removeTag(String key) async {
    if (!_canSend()) return;
    await _api.updateTags(_requireExternalId(), {key: null});
  }

  /// Add an email subscription for the current user.
  Future<void> addEmail(String email) async {
    if (!_canSend()) return;
    await _api.addSubscription(
      externalId: _requireExternalId(),
      type: SubscriptionType.email,
      token: email,
    );
  }

  /// Add an SMS subscription for the current user.
  Future<void> addSms(String phoneE164) async {
    if (!_canSend()) return;
    await _api.addSubscription(
      externalId: _requireExternalId(),
      type: SubscriptionType.sms,
      token: phoneE164,
    );
  }
}
