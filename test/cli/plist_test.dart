import 'package:flutter_test/flutter_test.dart';

import '../../cli/plist.dart';

void main() {
  test('setString inserts PayghaamAppGroup and is idempotent', () {
    const original = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Runner</string>
</dict>
</plist>
''';
    final doc = PlistDoc(original);
    expect(doc.setString('PayghaamAppGroup', 'group.com.app.payghaam'), isTrue);
    expect(doc.stringValue('PayghaamAppGroup'), 'group.com.app.payghaam');
    expect(doc.setString('PayghaamAppGroup', 'group.com.app.payghaam'), isFalse);
  });

  test('addArrayString appends remote-notification without duplicating', () {
    const original = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
	</array>
</dict>
</plist>
''';
    final doc = PlistDoc(original);
    expect(doc.addArrayString('UIBackgroundModes', 'remote-notification'), isTrue);
    expect(doc.arrayStrings('UIBackgroundModes'), ['fetch', 'remote-notification']);
    expect(doc.addArrayString('UIBackgroundModes', 'remote-notification'), isFalse);
  });

  test('addArrayString creates the array when missing', () {
    const original = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Runner</string>
</dict>
</plist>
''';
    final doc = PlistDoc(original);
    expect(
      doc.addArrayString('com.apple.security.application-groups', 'group.x.payghaam'),
      isTrue,
    );
    expect(
      doc.arrayStrings('com.apple.security.application-groups'),
      ['group.x.payghaam'],
    );
  });
}
