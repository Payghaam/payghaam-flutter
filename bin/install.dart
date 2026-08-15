import 'dart:io';

import '../cli/install.dart';

void main(List<String> args) async {
  exitCode = await runInstall(args);
}
