class TextEdit {
  TextEdit(this.content, {this.message});
  final String content;
  final String? message;
  bool get changed => message != null;
}

const nseTargetName = 'PayghaamNSE';

/// Ensures a CocoaPods target for the NSE that depends on the published
/// `Payghaam` pod. Copies `use_frameworks!` / `use_modular_headers!` from
/// the existing Podfile so linkage matches Runner.
TextEdit ensurePayghaamNseTarget(String podfile) {
  if (RegExp("target\\s+['\"]$nseTargetName['\"]").hasMatch(podfile)) {
    return TextEdit(podfile);
  }

  final useFrameworks = RegExp(
    r'^[ \t]*use_frameworks!.*$',
    multiLine: true,
  ).firstMatch(podfile)?.group(0);
  final modular = RegExp(
    r'^[ \t]*use_modular_headers!\s*$',
    multiLine: true,
  ).hasMatch(podfile);

  final buffer = StringBuffer()
    ..writeln()
    ..writeln("target '$nseTargetName' do");
  if (useFrameworks != null) {
    buffer.writeln(
        useFrameworks.startsWith(' ') ? useFrameworks : '  $useFrameworks');
  }
  if (modular) {
    buffer.writeln('  use_modular_headers!');
  }
  buffer
    ..writeln("  pod 'Payghaam'")
    ..writeln('end')
    ..writeln();

  final trimmed = podfile.endsWith('\n') ? podfile : '$podfile\n';
  return TextEdit(
    '$trimmed${buffer.toString()}',
    message: "Added CocoaPods target '$nseTargetName' with pod 'Payghaam'",
  );
}
