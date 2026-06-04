import 'package:dekon/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app name', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Dekon'), findsOneWidget);
  });
}
