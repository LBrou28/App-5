import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_5/features/auth/sign_in_page.dart';
import 'package:app_5/core/firebase/firebase_services.dart';

void main() {
  testWidgets('shows Google sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));

    expect(find.text('Where Did I Put It?'), findsOneWidget);
    if (FirebaseServices.emulatorsEnabled) {
      expect(find.text('Use local test account A'), findsOneWidget);
      expect(find.text('Use local test account B'), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
    } else {
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Use local test account A'), findsNothing);
    }
  });
}
