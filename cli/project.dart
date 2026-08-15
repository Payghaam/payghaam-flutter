import 'dart:io';
import 'dart:isolate';

/// Host Flutter app + the payghaam_flutter package that is running this CLI.
class InstallProject {
  InstallProject({
    required this.appRoot,
    required this.packageRoot,
    required this.androidDir,
    required this.iosDir,
  });

  final Directory appRoot;
  final Directory packageRoot;
  final Directory? androidDir;
  final Directory? iosDir;

  File get pubspec => File('${appRoot.path}/pubspec.yaml');

  File get nseSwiftSource =>
      File('${packageRoot.path}/ios_extension/NotificationService.swift');

  File get rubyNseScript => File('${packageRoot.path}/tool/ios_add_nse.rb');

  static Future<InstallProject> discover({Directory? from}) async {
    final appRoot = from ?? Directory.current;
    final pubspec = File('${appRoot.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw StateError(
        'No pubspec.yaml in ${appRoot.path}. Run this from your Flutter app root.',
      );
    }
    final pubspecText = pubspec.readAsStringSync();
    if (!pubspecText.contains('\nflutter:') &&
        !pubspecText.contains('\r\nflutter:') &&
        !RegExp(r'^flutter:', multiLine: true).hasMatch(pubspecText)) {
      throw StateError(
        '${pubspec.path} does not look like a Flutter app. Run this from the app root.',
      );
    }

    final packageRoot = await payghaamPackageRoot();
    final android = Directory('${appRoot.path}/android');
    final ios = Directory('${appRoot.path}/ios');
    return InstallProject(
      appRoot: appRoot,
      packageRoot: packageRoot,
      androidDir: android.existsSync() ? android : null,
      iosDir: ios.existsSync() ? ios : null,
    );
  }
}

/// Directory that contains this package's `pubspec.yaml` (pub-cache or path).
Future<Directory> payghaamPackageRoot() async {
  final resolved = await Isolate.resolvePackageUri(
    Uri.parse('package:payghaam_flutter/payghaam_flutter.dart'),
  );
  if (resolved == null) {
    throw StateError(
      'Cannot resolve package:payghaam_flutter. Is payghaam_flutter in pubspec.yaml?',
    );
  }
  return File.fromUri(resolved).parent.parent;
}

bool looksLikeFlutterAppPubspec(String text) {
  return RegExp(r'^flutter\s*:', multiLine: true).hasMatch(text);
}
