import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_callkit/main.dart';

void main() {
  testWidgets('renders CallKit example controls', (WidgetTester tester) async {
    await tester.pumpWidget(const CallKitExampleApp());

    expect(find.text('LiveKit CallKit Example'), findsOneWidget);
    expect(find.text('Start outgoing CallKit call'), findsOneWidget);
    expect(find.text('Simulate incoming call'), findsOneWidget);
  });
}
