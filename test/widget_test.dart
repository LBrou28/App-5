import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_5/features/auth/sign_in_page.dart';

void main() {
  testWidgets('shows Google sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));

    expect(find.text('Where Did I Put It?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
