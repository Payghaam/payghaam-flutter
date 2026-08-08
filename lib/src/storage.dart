import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistence for the current External ID and an anonymous device
/// id (used before the user logs in). Backed by shared_preferences.
class Storage {
  static const _kExternalId = 'payghaam.externalId';
  static const _kDeviceId = 'payghaam.deviceId';
  static const _kConsent = 'payghaam.consentGiven';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> getExternalId() async => (await _p).getString(_kExternalId);
  Future<void> setExternalId(String? id) async {
    final p = await _p;
    if (id == null) {
      await p.remove(_kExternalId);
    } else {
      await p.setString(_kExternalId, id);
    }
  }

  Future<bool> getConsent() async => (await _p).getBool(_kConsent) ?? false;
  Future<void> setConsent(bool v) async => (await _p).setBool(_kConsent, v);

  /// Stable anonymous device id, generated once and persisted.
  Future<String> deviceId() async {
    final p = await _p;
    var id = p.getString(_kDeviceId);
    if (id == null) {
      id = 'dev_${DateTime.now().microsecondsSinceEpoch}_${p.hashCode}';
      await p.setString(_kDeviceId, id);
    }
    return id;
  }
}
