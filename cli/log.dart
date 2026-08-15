import 'dart:io';

/// Collects CLI output so callers (and tests) can inspect it.
class InstallLog {
  InstallLog({this.dryRun = false});

  final bool dryRun;
  final List<String> lines = [];
  final List<String> changed = [];
  final List<String> remaining = [];
  final List<String> warnings = [];

  void printAll() {
    for (final line in lines) {
      stdout.writeln(line);
    }
  }

  void header(String text) => _add(text);

  void section(String title) {
    _add('');
    _add(title);
  }

  void changedLine(String message) {
    final prefix = dryRun ? '  would' : '  ✓';
    changed.add(message);
    _add('$prefix $message');
  }

  void ok(String message) => _add('  · $message');

  void remain(String message) {
    remaining.add(message);
  }

  void warn(String message) {
    warnings.add(message);
    _add('  ! $message');
  }

  void info(String message) => _add('  $message');

  void _add(String line) => lines.add(line);
}
