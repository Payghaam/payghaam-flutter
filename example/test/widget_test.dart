import 'package:payghaam_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders example app', (WidgetTester tester) async {
    await tester.pumpWidget(const PayghaamExampleApp());
    expect(find.text('Payghaam Example'), findsOneWidget);
  });
}
