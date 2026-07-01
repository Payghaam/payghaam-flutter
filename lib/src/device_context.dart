import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _methods = MethodChannel('engagekaro/methods');
const kEngageKaroSdkVersion = '0.1.0';

/// Auto-collected locale, device, and app metadata sent on identify / session pings.
class DeviceContext {
  final String? country;
  final String? language;
  final String? timezone;
  final String? os;
  final String? osVersion;
  final String? appVersion;
  final String? deviceModel;
  final String? sdkVersion;
  final String? pushPermission;
  final bool sessionStart;

  const DeviceContext({
    this.country,
    this.language,
    this.timezone,
    this.os,
    this.osVersion,
    this.appVersion,
    this.deviceModel,
    this.sdkVersion,
    this.pushPermission,
    this.sessionStart = false,
  });

  Map<String, dynamic> toJson() => {
        if (country != null) 'country': country,
        if (language != null) 'language': language,
        if (timezone != null) 'timezone': timezone,
        if (os != null) 'os': os,
        if (osVersion != null) 'osVersion': osVersion,
        if (appVersion != null) 'appVersion': appVersion,
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (sdkVersion != null) 'sdkVersion': sdkVersion,
        if (pushPermission != null) 'pushPermission': pushPermission,
        if (sessionStart) 'sessionStart': true,
      };

  static Future<DeviceContext> collect(
      {bool sessionStart = false, String? pushPermission}) async {
    Map<dynamic, dynamic>? native;
    try {
      native = await _methods
          .invokeMethod<Map<dynamic, dynamic>>('getDeviceContext');
    } catch (_) {
      native = null;
    }

    final locale = _readLocale();
    final fallbackOs = _fallbackOs();

    return DeviceContext(
      country: _str(native?['country']) ?? locale.countryCode,
      language: _str(native?['language']) ?? locale.languageCode,
      timezone: _str(native?['timezone']) ?? _fallbackTimezone(),
      os: _str(native?['os']) ?? fallbackOs,
      osVersion: _str(native?['osVersion']),
      appVersion: _str(native?['appVersion']),
      deviceModel: _str(native?['deviceModel']),
      sdkVersion: _str(native?['sdkVersion']) ?? kEngageKaroSdkVersion,
      pushPermission: pushPermission,
      sessionStart: sessionStart,
    );
  }

  static String? _str(dynamic v) => v is String && v.isNotEmpty ? v : null;

  static Locale _readLocale() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale;
    } catch (_) {
      return const Locale('en');
    }
  }

  static String? _fallbackTimezone() {
    try {
      return DateTime.now().timeZoneName;
    } catch (_) {
      return null;
    }
  }

  static String _fallbackOs() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }
}

/// Debounces foreground resumes — one session per 30 minutes of inactivity.
class SessionTracker {
  static const _gap = Duration(minutes: 30);
  DateTime? _lastSessionAt;

  bool noteForegroundResume() {
    final now = DateTime.now();
    if (_lastSessionAt != null && now.difference(_lastSessionAt!) < _gap) {
      return false;
    }
    _lastSessionAt = now;
    return true;
  }
}
