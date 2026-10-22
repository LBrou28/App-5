import 'location.dart';

/// Search and browse helpers that run over the items already loaded for a
/// household. Kept free of Flutter and Firebase so they are easy to test.

/// Case- and whitespace-insensitive key for comparing categories.
String normalizeCategory(String category) => category.trim().toLowerCase();

/// Display text for a category; items without one are "Uncategorized".
String categoryLabel(String category) => category.trim().isEmpty ? 'Uncategorized' : category.trim();

/// Returns the items that match every given condition.
///
/// [query] is split into words; an item matches when each word appears in its
/// name, category, notes, or location label (from [locationLabel]).
/// [category] limits results to one category ('' means uncategorized).
/// [favoritesOnly] limits results to ids in [favoriteIds].
List<StoredItem> filterItems(
  List<StoredItem> items, {
  String query = '',
  String? category,
  bool favoritesOnly = false,
  Set<String> favoriteIds = const {},
  String Function(StoredItem item)? locationLabel,
}) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
  final categoryKey = category == null ? null : normalizeCategory(category);
  return items.where((item) {
    if (favoritesOnly && !favoriteIds.contains(item.id)) return false;
    if (categoryKey != null && normalizeCategory(item.category) != categoryKey) return false;
    if (terms.isEmpty) return true;
    final haystack = [item.name, item.category, item.notes, locationLabel?.call(item) ?? ''].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }).toList();
}

class CategoryCount {
  const CategoryCount(this.category, this.count);

  /// The category as first written on an item ('' for uncategorized).
  final String category;
  final int count;
  String get label => categoryLabel(category);
}

/// Distinct categories (ignoring case), most used first, then alphabetical.
List<CategoryCount> categoryCounts(List<StoredItem> items) {
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final item in items) {
    final key = normalizeCategory(item.category);
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(key, () => item.category.trim());
  }
  final result = [for (final entry in counts.entries) CategoryCount(names[entry.key]!, entry.value)];
  result.sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return result;
}

/// The newest items that have a creation time, newest first.
List<StoredItem> recentlyAdded(List<StoredItem> items, {int limit = 5}) {
  final dated = items.where((item) => item.createdAt != null).toList()
    ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  return dated.take(limit).toList();
}
