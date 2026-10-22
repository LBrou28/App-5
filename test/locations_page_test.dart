import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_5/features/locations/location.dart';
import 'package:app_5/features/locations/locations_page.dart';

import 'package:app_5/features/items/item_details.dart';

import 'item_editor_test.dart' show TestRepository;

class TestUser implements User {
  @override
  String? get email => 'member@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PageRepository extends TestRepository {
  int deletions = 0;
  @override
  Stream<List<StorageLocation>> watchLocations() => Stream.value(const [
    StorageLocation(id: 'room', name: 'Garage', kind: LocationKind.room),
  ]);
  @override
  Stream<List<StoredItem>> watchItems() => Stream.value(const [
    StoredItem(
      id: 'hammer',
      name: 'Hammer',
      category: 'Tools',
      notes: 'Top shelf',
      locationId: 'room',
    ),
  ]);
  @override
  Stream<String> watchHouseholdName() => Stream.value('Shared home');
  @override
  Future<void> deleteItem(StoredItem item) async {
    deletions++;
  }

  @override
  Future<String> createInvitation() async => 'invitation-code';
  @override
  Future<String> joinHousehold(String code) async {
    if (code != 'invitation-code') throw StateError('bad code');
    return 'joined-home';
  }
}

class LiveRepository extends PageRepository {
  final items = StreamController<List<StoredItem>>.broadcast();
  @override
  Stream<List<StoredItem>> watchItems() => items.stream;
}

void main() {
  testWidgets(
    'item details show location and status; deletion requires confirmation',
    (tester) async {
      final repo = PageRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: LocationsPage(repository: repo, user: TestUser()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hammer'));
      await tester.pumpAndSettle();
      expect(find.text('Location: Garage'), findsOneWidget);
      expect(find.text('Borrowing status: Available'), findsOneWidget);
      expect(find.text('Category: Tools'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);
      await tester.tap(find.byTooltip('Delete item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 1);
    },
  );

  testWidgets('joining a household requests the shared context change', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: LocationsPage(
          repository: PageRepository(),
          user: TestUser(),
          onHouseholdChanged: (id) => selected = id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account and household'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join a household'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'invitation-code');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(selected, 'joined-home');
  });
  testWidgets('open details reflect remote edits and deletion', (tester) async {
    final repo = LiveRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemDetailsDialog(
            repository: repo,
            item: const StoredItem(id: 'item', name: 'Toolbox'),
            locations: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.items.add(const [
      StoredItem(
        id: 'item',
        name: 'Shared toolbox',
        notes: 'Borrowed by Sam',
        activeLoanId: 'loan',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Shared toolbox'), findsOneWidget);
    expect(find.text('Borrowing status: On loan'), findsOneWidget);
    repo.items.add(const []);
    await tester.pumpAndSettle();
    expect(
      find.text('This item was deleted from your household.'),
      findsOneWidget,
    );
    expect(find.text('Edit'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await repo.items.close();
  });
}
