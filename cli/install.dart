import 'dart:io';

import 'android.dart';
import 'args.dart';
import 'ios.dart';
import 'log.dart';
import 'project.dart';

/// Entry used by `bin/install.dart`. Returns a process exit code.
Future<int> runInstall(List<String> argv) async {
  final InstallArgs args;
  try {
    args = InstallArgs.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(usage);
    return 64;
  }

  if (args.help) {
    stdout.write(usage);
    return 0;
  }

  final InstallProject project;
  try {
    project = await InstallProject.discover();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    return 1;
  }

  final log = InstallLog(dryRun: args.dryRun);
  log.header(args.dryRun ? 'Payghaam install (dry run)' : 'Payghaam install');
  log.info('App:     ${project.appRoot.path}');
  log.info('Package: ${project.packageRoot.path}');

  final doAndroid = args.autoPlatforms ? project.androidDir != null : args.android;
  final doIos = args.autoPlatforms ? project.iosDir != null : args.ios;

  if (args.android && project.androidDir == null) {
    log.warn('--android was set but this app has no android/ directory');
  }
  if (args.ios && project.iosDir == null) {
    log.warn('--ios was set but this app has no ios/ directory');
  }

  if (doAndroid) {
    configureAndroid(project, log);
  }
  if (doIos) {
    configureIos(project, log, appGroupFlag: args.appGroup);
  }

  if (!doAndroid && !doIos) {
    log.warn(
      'Nothing to do — no android/ or ios/ directory, and no --android/--ios flag.',
    );
    log.printAll();
    return 1;
  }

  log.section('Dart (not modified)');
  log.info('Initialize push in your app, then share config with the NSE / FCM service:');
  log.info('');
  log.info("  import 'package:payghaam_flutter/payghaam_flutter.dart';");
  log.info('');
  log.info('  final push = PayghaamPushProvider();');
  log.info('  await Payghaam.instance.initialize(config, push: push);');
  log.info("  await Payghaam.instance.login('user-id');");
  log.info('  await push.shareConfig(');
  log.info("    appGroup: 'group.<your.bundle.id>.payghaam', // iOS only");
  log.info('    apiBase: config.baseUrl,');
  log.info('    apiKey: config.apiKey,');
  log.info("    externalId: 'user-id',");
  log.info('  );');

  if (log.remaining.isNotEmpty) {
    log.section('Still manual');
    for (final item in log.remaining.toSet()) {
      log.info('• $item');
    }
  }

  log.section(args.dryRun ? 'No files written (--dry-run).' : 'Done.');
  if (!args.dryRun && log.changed.isEmpty) {
    log.info('Everything the CLI can do was already in place.');
  }

  log.printAll();
  return 0;
}
