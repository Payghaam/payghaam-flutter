import 'package:flutter_test/flutter_test.dart';
import 'package:payghaam_flutter/src/config.dart';

void main() {
  group('PayghaamConfig.apiRoot', () {
    test('appends /api/sdk to a base URL without a trailing slash', () {
      const config = PayghaamConfig(
        appId: 'app-1',
        apiKey: 'key-1',
        baseUrl: 'https://api.yourhost.com',
      );
      expect(config.apiRoot, 'https://api.yourhost.com/api/sdk');
    });

    test('strips a trailing slash before appending /api/sdk', () {
      const config = PayghaamConfig(
        appId: 'app-1',
        apiKey: 'key-1',
        baseUrl: 'https://api.yourhost.com/',
      );
      expect(config.apiRoot, 'https://api.yourhost.com/api/sdk');
    });

    test('defaults requireConsent, debug, timeout, and onError', () {
      const config = PayghaamConfig(
        appId: 'app-1',
        apiKey: 'key-1',
        baseUrl: 'https://api.yourhost.com',
      );
      expect(config.requireConsent, isFalse);
      expect(config.debug, isFalse);
      expect(config.timeout, const Duration(seconds: 15));
      expect(config.onError, isNull);
    });
  });

  group('SubscriptionType.wire', () {
    test('maps every subscription type to its backend wire value', () {
      expect(SubscriptionType.androidPush.wire, 'ANDROID_PUSH');
      expect(SubscriptionType.iosPush.wire, 'IOS_PUSH');
      expect(SubscriptionType.webPush.wire, 'WEB_PUSH');
      expect(SubscriptionType.email.wire, 'EMAIL');
      expect(SubscriptionType.sms.wire, 'SMS');
    });
  });
}
