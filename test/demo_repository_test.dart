import 'package:flutter_test/flutter_test.dart';
import 'package:app_5/features/locations/demo_repository.dart';

void main() {
  test('demo changes remain local and loan safeguards still apply', () async {
    final repo = DemoLocationRepository();
    final other = DemoLocationRepository();
    final initial = await repo.watchItems().first;
    final loaned = initial.firstWhere((i) => i.isOnLoan);
    await expectLater(repo.deleteItem(loaned), throwsStateError);
    await repo.saveItem(
      draftId: 'test',
      name: ' Keys ',
      category: 'Personal',
      notes: 'Spare set',
      locationId: 'drawer',
    );
    final saved = (await repo.watchItems().first).firstWhere(
      (i) => i.id == 'test',
    );
    expect(saved.name, 'Keys');
    expect((await other.watchItems().first).any((i) => i.id == 'test'), false);
    await repo.deleteItem(saved);
    expect((await repo.watchItems().first).any((i) => i.id == 'test'), false);
  });
}
