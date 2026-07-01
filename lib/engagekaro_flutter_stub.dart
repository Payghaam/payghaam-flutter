import 'package:flutter/services.dart';

import 'src/method_handler.dart';

/// Desktop stub for the EngageKaro plugin. Push is not supported on desktop.
class EngagekaroFlutterPlugin {
  static void registerWith() {
    const MethodChannel('engagekaro/methods')
        .setMethodCallHandler(handleEngagekaroMethod);
  }
}
