import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/method_handler.dart';

/// Web stub for the Payghaam plugin. Push is not supported on web.
class PayghaamFlutterPlugin {
  static void registerWith(Registrar registrar) {
    MethodChannel(
      'payghaam/methods',
      const StandardMethodCodec(),
      registrar,
    ).setMethodCallHandler(handlePayghaamMethod);
  }
}
