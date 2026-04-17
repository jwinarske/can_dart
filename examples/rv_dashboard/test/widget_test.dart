import 'package:flutter_test/flutter_test.dart';

import 'package:rv_dashboard/main.dart';

void main() {
  testWidgets('App shell renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const RvDashboardApp());
    expect(find.text('RV-C DASHBOARD'), findsOneWidget);
  });
}
