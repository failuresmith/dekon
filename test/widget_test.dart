import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('renders app name', (tester) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Dekon'), findsOneWidget);
  });
}
