import 'dart:io';

import 'gradle.dart';
import 'log.dart';
import 'project.dart';

void configureAndroid(InstallProject project, InstallLog log) {
  final android = project.androidDir;
  if (android == null) {
    log.warn('No android/ directory — skipping Android');
    return;
  }

  log.section('Android');

  final appKts = File('${android.path}/app/build.gradle.kts');
  final appGroovy = File('${android.path}/app/build.gradle');
  File? appGradle;
  var kotlinDsl = false;
  if (appKts.existsSync()) {
    appGradle = appKts;
    kotlinDsl = true;
  } else if (appGroovy.existsSync()) {
    appGradle = appGroovy;
  }

  final appAlreadyWired =
      appGradle != null && hasGoogleServicesPlugin(appGradle.readAsStringSync());

  if (appAlreadyWired) {
    log.ok('Google services plugin is applied');
  } else {
    final settingsKts = File('${android.path}/settings.gradle.kts');
    final settingsGroovy = File('${android.path}/settings.gradle');
    if (settingsKts.existsSync()) {
      _applyEdits(settingsKts, log, [
        (src) => ensureSettingsGoogleServices(src, kotlinDsl: true),
      ]);
    } else if (settingsGroovy.existsSync()) {
      _applyEdits(settingsGroovy, log, [
        (src) => ensureSettingsGoogleServices(src, kotlinDsl: false),
      ]);
    }

    final projectGroovy = File('${android.path}/build.gradle');
    final projectKts = File('${android.path}/build.gradle.kts');
    if (projectGroovy.existsSync()) {
      _applyEdits(projectGroovy, log, [ensureBuildscriptClasspath]);
    } else if (projectKts.existsSync()) {
      _applyEdits(projectKts, log, [ensureBuildscriptClasspath]);
    }

    if (appGradle != null) {
      _applyEdits(appGradle, log, [
        (src) => ensureAppGoogleServices(src, kotlinDsl: kotlinDsl),
      ]);
    } else {
      log.warn('Could not find android/app/build.gradle(.kts)');
    }
  }

  if (appGradle != null) {
    _applyEdits(appGradle, log, [
      ensureMinSdk,
      ensureJvm17,
    ]);
  }

  if (_hasGoogleServicesJson(android)) {
    log.ok('google-services.json found');
  } else {
    log.remain(
      'Add android/app/google-services.json from the Firebase console '
      '(package name must match applicationId). This CLI will not invent that file.',
    );
  }

  log.remain(
    'Upload the matching FCM service-account JSON in the Payghaam dashboard → '
    'Project → Channels → Android · FCM.',
  );
  log.remain(
    'If you use a custom deep-link scheme, register it on the launcher activity '
    '(see ANDROID_SETUP.md). https:// URLs need no extra intent-filter.',
  );
}

void _applyEdits(
  File file,
  InstallLog log,
  List<TextEdit Function(String source)> editors,
) {
  if (!file.existsSync()) return;
  var content = file.readAsStringSync();
  final messages = <String>[];
  for (final editor in editors) {
    final result = editor(content);
    if (result.changed) {
      content = result.content;
      if (result.message != null) messages.add(result.message!);
    }
  }
  if (messages.isEmpty) return;
  if (!log.dryRun) {
    file.writeAsStringSync(content);
  }
  final rel = _relAndroid(file);
  for (final message in messages) {
    log.changedLine('$message ($rel)');
  }
}

String _relAndroid(File file) {
  final path = file.path.replaceAll('\\', '/');
  final idx = path.lastIndexOf('/android/');
  if (idx >= 0) return path.substring(idx + 1);
  return file.path;
}

bool _hasGoogleServicesJson(Directory android) {
  if (File('${android.path}/app/google-services.json').existsSync()) {
    return true;
  }
  final src = Directory('${android.path}/app/src');
  if (!src.existsSync()) return false;
  return src
      .listSync(recursive: true)
      .whereType<File>()
      .any((f) => f.path.endsWith('google-services.json'));
}
