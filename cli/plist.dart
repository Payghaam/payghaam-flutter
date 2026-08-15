/// Minimal XML plist helpers. Idempotent string/array edits for Info.plist
/// and `.entitlements` files. Preserves existing indent.
class PlistDoc {
  PlistDoc(this.content);

  String content;

  String get indent {
    final match = RegExp(r'\n(\t+| +)<key>').firstMatch(content);
    return match?.group(1) ?? '\t';
  }

  bool hasKey(String key) =>
      content.contains('<key>$key</key>');

  String? stringValue(String key) {
    final match = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(content);
    return match?.group(1);
  }

  List<String> arrayStrings(String key) {
    final block = _arrayBlock(key);
    if (block == null) return const [];
    return RegExp(r'<string>([^<]*)</string>')
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toList();
  }

  /// Returns true if the document changed.
  bool setString(String key, String value) {
    final existing = stringValue(key);
    if (existing == value) return false;
    if (existing != null) {
      content = content.replaceFirst(
        '<key>$key</key>${_ws()}<string>$existing</string>',
        '<key>$key</key>${_ws()}<string>$value</string>',
      );
      return true;
    }
    _insertInRootDict(
      '<key>$key</key>\n$indent<string>$value</string>',
    );
    return true;
  }

  /// Returns true if [value] was newly added to the array (or the array created).
  bool addArrayString(String key, String value) {
    final current = arrayStrings(key);
    if (current.contains(value)) return false;
    final blockMatch = _arrayBlockMatch(key);
    if (blockMatch != null) {
      final inner = blockMatch.group(1)!;
      final innerIndent = indent + indent;
      final insertion = inner.endsWith('\n')
          ? '$inner$innerIndent<string>$value</string>\n$indent'
          : '$inner\n$innerIndent<string>$value</string>\n$indent';
      content = content.replaceFirst(
        blockMatch.group(0)!,
        '<key>$key</key>${_ws()}<array>$insertion</array>',
      );
      return true;
    }
    final innerIndent = indent + indent;
    _insertInRootDict(
      '<key>$key</key>\n$indent<array>\n$innerIndent<string>$value</string>\n$indent</array>',
    );
    return true;
  }

  String _ws() {
    final match = RegExp(r'<key>[^<]+</key>(\s*)<').firstMatch(content);
    return match?.group(1) ?? '\n$indent';
  }

  String? _arrayBlock(String key) => _arrayBlockMatch(key)?.group(1);

  RegExpMatch? _arrayBlockMatch(String key) {
    return RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(content);
  }

  void _insertInRootDict(String xml) {
    final close = content.lastIndexOf('</dict>');
    if (close < 0) {
      throw FormatException('Plist is missing a closing </dict>');
    }
    final before = content.substring(0, close);
    final needsNewline = !before.endsWith('\n');
    content =
        '${needsNewline ? '$before\n' : before}$indent$xml\n${content.substring(close)}';
  }
}

String entitlementsTemplate({
  required String appGroup,
  String apsEnvironment = 'development',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>$apsEnvironment</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$appGroup</string>
	</array>
</dict>
</plist>
''';
}

String nseInfoPlistTemplate(String appGroup) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>PayghaamNSE</string>
	<key>CFBundleName</key>
	<string>PayghaamNSE</string>
	<key>CFBundleIdentifier</key>
	<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleExecutable</key>
	<string>\$(EXECUTABLE_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>\$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>\$(FLUTTER_BUILD_NUMBER)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.usernotifications.service</string>
		<key>NSExtensionPrincipalClass</key>
		<string>\$(PRODUCT_MODULE_NAME).NotificationService</string>
	</dict>
	<key>PayghaamAppGroup</key>
	<string>$appGroup</string>
</dict>
</plist>
''';
}

String nseEntitlementsTemplate(String appGroup) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$appGroup</string>
	</array>
</dict>
</plist>
''';
}
