import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_5/features/items/item_editor.dart';
import 'package:app_5/features/locations/location.dart';
import 'package:app_5/features/locations/location_repository.dart';

class TestImagePicker extends ImagePicker {
  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();
}

class TestRepository implements LocationRepository {
  Map<String, dynamic>? saved;
  bool fail = false;
  @override
  String newItemId() => 'stable-draft';
  @override
  Future<Uint8List?> loadPhoto(String path) async =>
      throw StateError('offline');
  @override
  Future<void> saveItem({
    String? draftId,
    StoredItem? existing,
    required String name,
    required String category,
    required String notes,
    String? locationId,
    Uint8List? photo,
    String? photoType,
    bool removePhoto = false,
  }) async {
    saved = {
      'draftId': draftId,
      'existing': existing,
      'name': name,
      'category': category,
      'notes': notes,
      'locationId': locationId,
      'removePhoto': removePhoto,
    };
    if (fail) throw StateError('offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openEditor(
  WidgetTester tester,
  TestRepository repository, {
  StoredItem? item,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => ItemEditor(
                repository: repository,
                imagePicker: TestImagePicker(),
                locations: const [
                  StorageLocation(
                    id: 'room',
                    name: 'Garage',
                    kind: LocationKind.room,
                  ),
                ],
                existing: item,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requires a name, trims item details and saves a stable draft', (
    tester,
  ) async {
    final repo = TestRepository();
    await openEditor(tester, repo);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an item name.'), findsOneWidget);
    expect(repo.saved, isNull);
    await tester.enterText(find.byType(TextFormField).at(0), '  Toolbox  ');
    await tester.enterText(find.byType(TextFormField).at(1), ' Tools ');
    await tester.enterText(find.byType(TextFormField).at(2), ' Top shelf ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved?['name'], 'Toolbox');
    expect(repo.saved?['category'], 'Tools');
    expect(repo.saved?['notes'], 'Top shelf');
    expect(repo.saved?['draftId'], 'stable-draft');
    expect(find.text('New item'), findsNothing);
  });

  testWidgets(
    'editing preserves the item identity and supports removing its photo',
    (tester) async {
      final repo = TestRepository();
      const item = StoredItem(
        id: 'item',
        name: 'Hammer',
        category: 'Tools',
        notes: 'Original',
        locationId: 'room',
        photoPath: 'photo',
        revision: 3,
      );
      await openEditor(tester, repo, item: item);
      expect(find.text('Hammer'), findsOneWidget);
      expect(find.text('Garage'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved?['existing'], same(item));
      expect(repo.saved?['removePhoto'], true);
      expect(repo.saved?['locationId'], 'room');
    },
  );

  testWidgets('failed save retains input for retry; cancellation never saves', (
    tester,
  ) async {
    final repo = TestRepository()..fail = true;
    await openEditor(tester, repo);
    await tester.enterText(find.byType(TextFormField).first, 'Passport');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save item.'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    final id = repo.saved?['draftId'];
    repo.fail = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved?['draftId'], id);
    final cancelRepo = TestRepository();
    await openEditor(tester, cancelRepo);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelRepo.saved, isNull);
  });
}
