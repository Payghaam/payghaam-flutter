import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight persistence for the current External ID and an anonymous device
/// id (used before the user logs in). Backed by shared_preferences.
class Storage {
  static const _kExternalId = 'payghaam.externalId';
  static const _kDeviceId = 'payghaam.deviceId';
  static const _kAnonymousId = 'payghaam.anonymousId';
  static const _kLanguage = 'payghaam.language';
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

  Future<String> getAnonymousId() async {
    final p = await _p;
    var id = p.getString(_kAnonymousId);
    if (id == null || id.isEmpty) {
      id = _uuid();
      await p.setString(_kAnonymousId, id);
    }
    return id;
  }

  Future<String> resetAnonymousId() async {
    final p = await _p;
    final newId = _uuid();
    await p.setString(_kAnonymousId, newId);
    return newId;
  }

  Future<String?> getLanguage() async => (await _p).getString(_kLanguage);

  Future<void> setLanguage(String? lang) async {
    final p = await _p;
    if (lang == null) {
      await p.remove(_kLanguage);
    } else {
      await p.setString(_kLanguage, lang);
    }
  }

  static String _uuid() {
    final r = math.Random();
    String hex(int len) =>
        List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
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
