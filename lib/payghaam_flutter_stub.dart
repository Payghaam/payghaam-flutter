import 'package:flutter/services.dart';

import 'src/method_handler.dart';

/// Desktop stub for the Payghaam plugin. Push is not supported on desktop.
class PayghaamFlutterPlugin {
  static void registerWith() {
    const MethodChannel(
      'payghaam/methods',
    ).setMethodCallHandler(handlePayghaamMethod);
  }
}
