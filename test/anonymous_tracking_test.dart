import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payghaam_flutter/src/storage.dart';
import 'package:payghaam_flutter/src/user_manager.dart';
import 'package:payghaam_flutter/src/api_bridge.dart';
import 'package:payghaam_flutter/src/api_client.dart';
import 'package:payghaam_flutter/src/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Storage generates and persists anonymousId', () async {
    final storage = Storage();
    final anonId1 = await storage.getAnonymousId();
    expect(anonId1, isNotEmpty);

    final anonId2 = await storage.getAnonymousId();
    expect(anonId2, equals(anonId1));

    final anonId3 = await storage.resetAnonymousId();
    expect(anonId3, isNotEmpty);
    expect(anonId3, isNot(equals(anonId1)));
  });

  test('Storage persists language preference', () async {
    final storage = Storage();
    expect(await storage.getLanguage(), isNull);

    await storage.setLanguage('ar');
    expect(await storage.getLanguage(), equals('ar'));

    await storage.setLanguage(null);
    expect(await storage.getLanguage(), isNull);
  });

  test('UserManager allows setting tags, language, and aliases for anonymous users', () async {
    final config = PayghaamConfig(
      appId: 'app_1',
      apiKey: 'pk_live_123',
      baseUrl: 'http://localhost:3000',
    );
    final mockHttp = MockClient((request) async {
      return http.Response('{"ok": true}', 200);
    });
    final api = ApiClient(config, client: mockHttp);
    final bridge = ApiBridge();
    var languageSet = '';

    final user = UserManager(
      bridge,
      api,
      () => null, // externalId is null (anonymous user)
      () => 'anon_123',
      () => 'en',
      () => true,
      onLanguageChanged: (lang) async {
        languageSet = lang ?? '';
      },
    );

    await user.setLanguage('ar');
    expect(languageSet, equals('ar'));

    await user.addTag('tier', 'free');
    await user.addAlias('loyalty_id', 'loyalty_999');
  });
}
