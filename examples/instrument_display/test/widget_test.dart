import 'package:flutter_test/flutter_test.dart';

import 'package:instrument_display/main.dart';

void main() {
  testWidgets('App shell renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const InstrumentDisplayApp());
    expect(find.text('NMEA 2000 INSTRUMENT DISPLAY'), findsOneWidget);
  });
}
