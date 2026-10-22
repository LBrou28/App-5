import 'package:app_5/core/theme/app_theme.dart';
import 'package:app_5/features/locations/location_repository.dart';
import 'package:app_5/features/locations/locations_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestUser extends Fake implements User {
  @override
  String get uid => 'member';
  @override
  String? get displayName => 'Test member';
  @override
  String? get email => 'member@example.com';
}

void main() {
  testWidgets(
    'discovery and search retain household and borrowing navigation',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: LocationsPage(
            repository: LocationRepository.demo(),
            user: _TestUser(),
            onHouseholdChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Where did I put…?'), findsOneWidget);
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'keys');
      await tester.pumpAndSettle();
      expect(find.text('Spare keys'), findsOneWidget);
      expect(find.text('Hammer'), findsNothing);
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Account & household'), findsOneWidget);
      expect(find.text('Borrowed items'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
