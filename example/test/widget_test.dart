import 'package:engagekaro_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders example app', (WidgetTester tester) async {
    await tester.pumpWidget(const EngageKaroExampleApp());
    expect(find.text('EngageKaro Example'), findsOneWidget);
  });
}
