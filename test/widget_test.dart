import 'package:flutter_test/flutter_test.dart';
import 'package:app_5/main.dart';

void main() {
  testWidgets('starts with an empty inventory', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Your items'), findsOneWidget);
    expect(find.text('No items yet'), findsOneWidget);
  });
}
