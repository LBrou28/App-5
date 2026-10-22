import 'package:flutter_test/flutter_test.dart';

import 'package:app_5/features/locations/item_filter.dart';
import 'package:app_5/features/locations/location.dart';

void main() {
  final items = [
    StoredItem(id: 'keys', name: 'Spare keys', category: 'Household', notes: 'Back door', locationId: 'drawer', createdAt: DateTime(2026, 1, 3)),
    StoredItem(id: 'hammer', name: 'Hammer', category: 'Tools', locationId: 'garage', createdAt: DateTime(2026, 1, 5)),
    StoredItem(id: 'drill', name: 'Cordless drill', category: 'tools ', locationId: 'garage', createdAt: DateTime(2026, 1, 1)),
    const StoredItem(id: 'passport', name: 'Passport', notes: 'Renew in 2028'),
  ];
  String label(StoredItem item) => switch (item.locationId) { 'drawer' => 'Bedroom → Top drawer', 'garage' => 'Garage', _ => 'Unassigned' };
  List<String> ids(List<StoredItem> list) => list.map((item) => item.id).toList();

  group('filterItems', () {
    test('returns everything with no conditions', () {
      expect(ids(filterItems(items)), ['keys', 'hammer', 'drill', 'passport']);
    });

    test('matches name, notes, category and location, ignoring case', () {
      expect(ids(filterItems(items, query: 'HAMMER')), ['hammer']);
      expect(ids(filterItems(items, query: 'renew')), ['passport']);
      expect(ids(filterItems(items, query: 'tools')), ['hammer', 'drill']);
      expect(ids(filterItems(items, query: 'drawer', locationLabel: label)), ['keys']);
    });

    test('requires every word to match', () {
      expect(ids(filterItems(items, query: 'garage drill', locationLabel: label)), ['drill']);
      expect(ids(filterItems(items, query: 'garage passport', locationLabel: label)), isEmpty);
    });

    test('filters by category ignoring case and spaces, and by uncategorized', () {
      expect(ids(filterItems(items, category: 'Tools')), ['hammer', 'drill']);
      expect(ids(filterItems(items, category: '')), ['passport']);
    });

    test('filters to favorites and combines with other conditions', () {
      expect(ids(filterItems(items, favoritesOnly: true, favoriteIds: {'drill', 'passport'})), ['drill', 'passport']);
      expect(ids(filterItems(items, favoritesOnly: true, favoriteIds: {'drill', 'passport'}, category: 'tools')), ['drill']);
    });
  });

  test('categoryCounts merges case variants and sorts by count then name', () {
    final counts = categoryCounts(items);
    expect(counts.map((count) => '${count.label}:${count.count}'), ['Tools:2', 'Household:1', 'Uncategorized:1']);
  });

  test('recentlyAdded sorts newest first and skips undated items', () {
    expect(ids(recentlyAdded(items, limit: 2)), ['hammer', 'keys']);
    expect(ids(recentlyAdded(items)), ['hammer', 'keys', 'drill']);
  });
}
