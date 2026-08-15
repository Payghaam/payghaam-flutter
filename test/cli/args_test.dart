import 'package:flutter_test/flutter_test.dart';

import '../../cli/args.dart';

void main() {
  test('parses platform flags, app group, and dry-run', () {
    final args = InstallArgs.parse([
      '--ios',
      '--android',
      '--dry-run',
      '--app-group=group.com.example.app.payghaam',
    ]);
    expect(args.ios, isTrue);
    expect(args.android, isTrue);
    expect(args.dryRun, isTrue);
    expect(args.appGroup, 'group.com.example.app.payghaam');
    expect(args.autoPlatforms, isFalse);
  });

  test('no flags means auto-detect platforms', () {
    final args = InstallArgs.parse([]);
    expect(args.autoPlatforms, isTrue);
    expect(args.help, isFalse);
  });

  test('rejects unknown flags', () {
    expect(() => InstallArgs.parse(['--explode']), throwsFormatException);
  });

  test('requires a value for --app-group=', () {
    expect(() => InstallArgs.parse(['--app-group=']), throwsFormatException);
  });
}
