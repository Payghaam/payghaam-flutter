const googleServicesVersion = '4.4.2';

class TextEdit {
  TextEdit(this.content, {this.message});

  final String content;
  final String? message;
  bool get changed => message != null;
}

bool hasGoogleServicesPlugin(String source) {
  return source.contains('com.google.gms.google-services') ||
      source.contains("id 'com.google.gms.google-services'") ||
      source.contains('id("com.google.gms.google-services")') ||
      source.contains("apply plugin: 'com.google.gms.google-services'") ||
      source.contains('apply plugin: "com.google.gms.google-services"') ||
      source.contains("id 'com.google.gms.google-services'") ||
      source.contains('id "com.google.gms.google-services"');
}

/// Adds the Google services plugin to a `plugins { }` block, or appends
/// `apply plugin` for legacy Groovy files.
TextEdit ensureAppGoogleServices(String source, {required bool kotlinDsl}) {
  if (hasGoogleServicesPlugin(source)) {
    return TextEdit(source);
  }

  final plugins = _pluginsBlock(source);
  if (plugins != null) {
    final pluginLine = kotlinDsl
        ? '    id("com.google.gms.google-services")'
        : '    id "com.google.gms.google-services"';
    final updated = _insertBeforeClosingBrace(
      source,
      plugins.start,
      plugins.end,
      pluginLine,
    );
    return TextEdit(
      updated,
      message: 'Applied Google services plugin in the app plugins block',
    );
  }

  if (!kotlinDsl) {
    final apply = "apply plugin: 'com.google.gms.google-services'\n";
    final trimmed = source.endsWith('\n') ? source : '$source\n';
    return TextEdit(
      '$trimmed\n$apply',
      message: "Applied plugin: 'com.google.gms.google-services'",
    );
  }

  return TextEdit(source);
}

/// Registers `com.google.gms.google-services` in settings.gradle(.kts) `plugins { }`.
TextEdit ensureSettingsGoogleServices(String source,
    {required bool kotlinDsl}) {
  if (hasGoogleServicesPlugin(source)) {
    return TextEdit(source);
  }
  final plugins = _pluginsBlock(source);
  if (plugins == null) {
    return TextEdit(source);
  }
  final pluginLine = kotlinDsl
      ? '    id("com.google.gms.google-services") version "$googleServicesVersion" apply false'
      : '    id "com.google.gms.google-services" version "$googleServicesVersion" apply false';
  final updated = _insertBeforeClosingBrace(
    source,
    plugins.start,
    plugins.end,
    pluginLine,
  );
  return TextEdit(
    updated,
    message: 'Registered Google services plugin in settings plugins block',
  );
}

/// Legacy project-level `buildscript { dependencies { classpath ... } }`.
TextEdit ensureBuildscriptClasspath(String source) {
  if (source.contains('com.google.gms:google-services')) {
    return TextEdit(source);
  }
  final deps = RegExp(
    r'buildscript\s*\{.*?dependencies\s*\{',
    dotAll: true,
  ).firstMatch(source);
  if (deps == null) {
    return TextEdit(source);
  }
  final insertAt = deps.end;
  const line =
      "\n        classpath 'com.google.gms:google-services:$googleServicesVersion'";
  final updated =
      '${source.substring(0, insertAt)}$line${source.substring(insertAt)}';
  return TextEdit(
    updated,
    message: 'Added Google services classpath in project build.gradle',
  );
}

/// Bumps a numeric minSdk / minSdkVersion below 21. Leaves `flutter.minSdkVersion` alone.
TextEdit ensureMinSdk(String source, {int minimum = 21}) {
  final patterns = <RegExp>[
    RegExp(r'(minSdk\s*=\s*)(\d+)'),
    RegExp(r'(minSdkVersion\s+)(\d+)'),
  ];
  var content = source;
  String? message;
  for (final pattern in patterns) {
    content = content.replaceAllMapped(pattern, (m) {
      final current = int.parse(m.group(2)!);
      if (current >= minimum) return m.group(0)!;
      message = 'Raised minSdk from $current to $minimum';
      return '${m.group(1)}$minimum';
    });
  }
  return TextEdit(content, message: message);
}

/// Bumps Java/Kotlin JVM target to 17 when an older target is declared.
TextEdit ensureJvm17(String source) {
  var content = source;
  final replacements = <RegExp, String>{
    RegExp(r'JavaVersion\.VERSION_1_8'): 'JavaVersion.VERSION_17',
    RegExp(r'JavaVersion\.VERSION_11'): 'JavaVersion.VERSION_17',
    RegExp(r'''jvmTarget\s*=\s*['"]1\.8['"]'''): "jvmTarget = '17'",
    RegExp(r'''jvmTarget\s*=\s*['"]11['"]'''): "jvmTarget = '17'",
    RegExp(r'jvmTarget\s*=\s*1\.8\b'): 'jvmTarget = 17',
    RegExp(r'jvmTarget\s*=\s*11\b'): 'jvmTarget = 17',
  };
  String? message;
  replacements.forEach((pattern, replacement) {
    if (pattern.hasMatch(content)) {
      content = content.replaceAll(pattern, replacement);
      message = 'Set JVM target to 17 (required by the Payghaam Android SDK)';
    }
  });
  return TextEdit(content, message: message);
}

class _Block {
  _Block(this.start, this.end);
  final int start;
  final int end;
}

/// First top-level-ish `plugins { ... }` block (brace-matched).
_Block? _pluginsBlock(String source) {
  final start = RegExp(r'plugins\s*\{').firstMatch(source);
  if (start == null) return null;
  final open = start.end - 1;
  final close = _matchingBrace(source, open);
  if (close < 0) return null;
  return _Block(open, close);
}

int _matchingBrace(String source, int openIndex) {
  var depth = 0;
  var inString = false;
  var stringChar = '';
  for (var i = openIndex; i < source.length; i++) {
    final c = source[i];
    if (inString) {
      if (c == stringChar && source[i - 1] != '\\') inString = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inString = true;
      stringChar = c;
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String _insertBeforeClosingBrace(
  String source,
  int open,
  int close,
  String line,
) {
  final inner = source.substring(open + 1, close);
  final prefix = source.substring(0, close);
  final needsNewline = !prefix.endsWith('\n');
  final addition = '${needsNewline ? '\n' : ''}$line\n';
  // Keep a blank-line-free plugins block; preserve inner content as-is.
  if (inner.trim().isEmpty) {
    return '${source.substring(0, open + 1)}\n$line\n${source.substring(close)}';
  }
  return '${source.substring(0, close)}$addition${source.substring(close)}';
}
