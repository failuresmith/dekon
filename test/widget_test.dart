import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('renders compact root shell title', (tester) async {
    final repository = await createEnglishTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Dekon'), findsNothing);
    expect(find.text('Sell'), findsWidgets);
  });
}
