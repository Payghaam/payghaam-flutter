import 'package:flutter_test/flutter_test.dart';

import '../../cli/podfile.dart';

void main() {
  test('appends a PayghaamNSE target matching use_frameworks', () {
    const src = '''
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
''';
    final edit = ensurePayghaamNseTarget(src);
    expect(edit.changed, isTrue);
    expect(edit.content, contains("target 'PayghaamNSE' do"));
    expect(edit.content, contains("pod 'Payghaam'"));
    expect(edit.content, contains('use_frameworks!'));
    expect(edit.content, contains('use_modular_headers!'));
    expect(ensurePayghaamNseTarget(edit.content).changed, isFalse);
  });

  test('is a no-op when the NSE target already exists', () {
    const src = '''
target 'Runner' do
  use_frameworks!
end

target 'PayghaamNSE' do
  pod 'Payghaam'
end
''';
    expect(ensurePayghaamNseTarget(src).changed, isFalse);
  });
}
