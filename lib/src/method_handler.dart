import 'package:flutter/services.dart';

/// Shared method-channel handler for platforms without native push (web, desktop).
Future<dynamic> handleEngagekaroMethod(MethodCall call) async {
  switch (call.method) {
    case 'requestPermission':
      return false;
    case 'registerForRemoteNotifications':
    case 'setSharedConfig':
      return null;
    case 'getToken':
    case 'getInitialNotification':
      return null;
    case 'getDeviceContext':
      return <String, dynamic>{};
    default:
      throw MissingPluginException(
          'No implementation found for ${call.method}');
  }
}
