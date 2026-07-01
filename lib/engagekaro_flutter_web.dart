import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/method_handler.dart';

/// Web stub for the EngageKaro plugin. Push is not supported on web.
class EngagekaroFlutterPlugin {
  static void registerWith(Registrar registrar) {
    MethodChannel(
      'engagekaro/methods',
      const StandardMethodCodec(),
      registrar,
    ).setMethodCallHandler(handleEngagekaroMethod);
  }
}
