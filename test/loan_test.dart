import 'package:app_5/features/sharing/sharing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final due = DateTime.utc(2026, 10, 25, 18);
  Loan loan({DateTime? returned}) => Loan(
    id: 'loan',
    itemId: 'item',
    borrower: 'Alex',
    recordedBy: 'member',
    dueDate: due,
    borrowedAt: due.subtract(const Duration(days: 7)),
    returnedAt: returned,
  );
  test('active loan becomes overdue only after its return time', () {
    expect(loan().overdueAt(due.subtract(const Duration(seconds: 1))), isFalse);
    expect(loan().overdueAt(due), isFalse);
    expect(loan().overdueAt(due.add(const Duration(seconds: 1))), isTrue);
  });
  test('returned loan retains dates and never appears overdue', () {
    final returned = loan(returned: due.add(const Duration(days: 1)));
    expect(returned.active, isFalse);
    expect(returned.overdueAt(due.add(const Duration(days: 2))), isFalse);
    expect(returned.dueDate, due);
    expect(returned.borrower, 'Alex');
  });
  test('history keeps the recorded item name after rename or deletion', () {
    final returned = Loan(
      id: 'loan',
      itemId: 'item',
      itemName: 'Drill',
      borrower: 'Alex',
      recordedBy: 'member',
      dueDate: due,
      borrowedAt: due,
      returnedAt: due,
    );
    expect(returned.displayName('Renamed drill'), 'Drill');
    expect(returned.displayName(null), 'Drill');
    expect(loan().displayName('Existing item'), 'Existing item');
    expect(loan().displayName(null), 'Removed item');
  });
}
