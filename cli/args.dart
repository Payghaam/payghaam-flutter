/// Parsed flags for `dart run payghaam_flutter:install`.
class InstallArgs {
  InstallArgs({
    required this.android,
    required this.ios,
    required this.dryRun,
    required this.help,
    this.appGroup,
  });

  /// When both [android] and [ios] are false, the CLI auto-detects platforms.
  final bool android;
  final bool ios;
  final bool dryRun;
  final bool help;
  final String? appGroup;

  bool get autoPlatforms => !android && !ios;

  static InstallArgs parse(List<String> argv) {
    var android = false;
    var ios = false;
    var dryRun = false;
    var help = false;
    String? appGroup;

    for (final raw in argv) {
      if (raw == '--android') {
        android = true;
      } else if (raw == '--ios') {
        ios = true;
      } else if (raw == '--dry-run') {
        dryRun = true;
      } else if (raw == '--help' || raw == '-h') {
        help = true;
      } else if (raw.startsWith('--app-group=')) {
        appGroup = raw.substring('--app-group='.length).trim();
        if (appGroup.isEmpty) {
          throw FormatException('--app-group= requires a value');
        }
      } else if (raw == '--app-group') {
        throw FormatException('Use --app-group=<id>, e.g. --app-group=group.com.app.payghaam');
      } else {
        throw FormatException('Unknown argument: $raw');
      }
    }

    return InstallArgs(
      android: android,
      ios: ios,
      dryRun: dryRun,
      help: help,
      appGroup: appGroup,
    );
  }
}

const usage = '''
Configure a Flutter app for Payghaam push (Android FCM + iOS APNs / NSE).

Usage:
  dart run payghaam_flutter:install [options]

Run from your Flutter app root (the directory with pubspec.yaml).

Options:
  --android              Only configure Android
  --ios                  Only configure iOS
  --app-group=<id>       iOS App Group id (default: group.<bundle_id>.payghaam)
  --dry-run              Print what would change without writing files
  -h, --help             Show this help

The command is idempotent — safe to re-run.
''';
