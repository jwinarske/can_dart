import 'package:flutter_test/flutter_test.dart';

import 'package:obdii_monitor/main.dart';

void main() {
  testWidgets('App renders connection screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ObdiiMonitorApp());
    expect(find.text('OBD-II Monitor'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
