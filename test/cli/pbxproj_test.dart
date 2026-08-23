import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../cli/pbxproj.dart';

void main() {
  test('adds PayghaamNSE to a stock Flutter Runner.xcodeproj and is idempotent',
      () {
    final fixture = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    );
    expect(fixture.existsSync(), isTrue,
        reason: 'example app pbxproj is the fixture');

    final editor = PbxprojEditor(fixture.readAsStringSync());
    expect(editor.appTargetId, isNotNull);
    expect(editor.defaultBundleId(), 'com.example.payghaamExample');
    expect(editor.hasNseTarget, isFalse);

    final configs = editor.runnerConfigs();
    expect(configs.map((c) => c.name).toSet(), {'Debug', 'Release', 'Profile'});

    final message = editor.addNseTarget(
      deploymentTarget: '15.0',
      entitlementsRelPath: 'PayghaamNSE/PayghaamNSE.entitlements',
      infoPlistRelPath: 'PayghaamNSE/Info.plist',
    );
    expect(message, contains('PayghaamNSE'));
    expect(editor.hasNseTarget, isTrue);
    expect(editor.content, contains('name = PayghaamNSE;'));
    expect(
      editor.content,
      contains('productType = "com.apple.product-type.app-extension"'),
    );
    expect(editor.content, contains('NotificationService.swift in Sources'));
    expect(editor.content, contains('Embed Foundation Extensions'));
    expect(editor.content, contains('dstSubfolderSpec = 13;'));
    expect(
      editor.content,
      contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.payghaamExample.PayghaamNSE;'),
    );
    expect(editor.content, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;'));

    final spm = editor.ensurePayghaamSpm();
    expect(spm, contains('Payghaam'));
    expect(editor.content, contains('github.com/payghaam/payghaam-ios'));
    expect(editor.content, contains('productName = Payghaam;'));
    expect(editor.ensurePayghaamSpm(), isNull);

    expect(
      editor.addNseTarget(
        deploymentTarget: '15.0',
        entitlementsRelPath: 'PayghaamNSE/PayghaamNSE.entitlements',
        infoPlistRelPath: 'PayghaamNSE/Info.plist',
      ),
      isNull,
    );
  });

  test('ensureRunnerEntitlements sets CODE_SIGN_ENTITLEMENTS once', () {
    final fixture = File('example/ios/Runner.xcodeproj/project.pbxproj');
    final editor = PbxprojEditor(fixture.readAsStringSync());
    expect(
        editor.ensureRunnerEntitlements('Runner/Runner.entitlements'), isTrue);
    expect(
        editor.content
            .contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
        isTrue);
    expect(
        editor.ensureRunnerEntitlements('Runner/Runner.entitlements'), isFalse);
  });

  test('maxIosVersion prefers the higher deployment target', () {
    expect(maxIosVersion('13.0', '15.0'), '15.0');
    expect(maxIosVersion('16.6', '15.0'), '16.6');
    expect(maxIosVersion('15.0', '15.0'), '15.0');
  });
}
