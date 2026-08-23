import 'package:flutter_test/flutter_test.dart';
import 'package:payghaam_flutter/src/device_context.dart';

void main() {
  test('first resume is a new session', () {
    final sessions = SessionTracker();
    expect(sessions.noteForegroundResume(), isTrue);
  });

  test('resume within 30s is the same session', () {
    final sessions = SessionTracker();
    expect(sessions.noteForegroundResume(), isTrue);
    expect(sessions.noteForegroundResume(), isFalse);
  });
}
