import 'package:flutter/material.dart';

import '../locations/item_filter.dart';
import '../locations/location.dart';
import '../locations/widgets.dart';

/// Home overview: search shortcut, totals, favorites, categories, newest items
/// and items that still need a location. Reads only what is already loaded.
class DiscoverView extends StatelessWidget {
  const DiscoverView({
    super.key,
    required this.items,
    required this.locationCount,
    required this.favoriteIds,
    required this.actions,
    required this.onSearch,
    required this.onShowAll,
    required this.onShowFavorites,
    required this.onShowCategory,
    required this.onShowLocations,
    required this.onAddItem,
  });

  final List<StoredItem> items;
  final int locationCount;
  final Set<String> favoriteIds;
  final ItemActions actions;
  final VoidCallback onSearch;
  final VoidCallback onShowAll;
  final VoidCallback onShowFavorites;
  final ValueChanged<String> onShowCategory;
  final VoidCallback onShowLocations;
  final VoidCallback onAddItem;

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context) {
    final favorites = items.where((item) => favoriteIds.contains(item.id)).toList();
    final recent = recentlyAdded(items, limit: _previewCount);
    final unassigned = items.where((item) => actions.locationLabel(item) == null).toList();
    final categories = categoryCounts(items);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SearchLauncher(onTap: onSearch),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _StatTile(icon: Icons.sell_outlined, label: 'Items', value: items.length, onTap: onShowAll)),
          const SizedBox(width: 12),
          Expanded(child: _StatTile(icon: Icons.door_front_door_outlined, label: 'Locations', value: locationCount, onTap: onShowLocations)),
          const SizedBox(width: 12),
          Expanded(child: _StatTile(icon: Icons.star_outline_rounded, label: 'Favorites', value: favorites.length, onTap: onShowFavorites)),
        ]),
        if (items.isEmpty) ...[
          const SizedBox(height: 24),
          EmptyState(
            icon: Icons.explore_outlined,
            title: 'Nothing to discover yet',
            detail: 'Add your first item and it will show up here, along with your favorites and categories.',
            action: FilledButton.icon(onPressed: actions.working ? null : onAddItem, icon: const Icon(Icons.add), label: const Text('Add item')),
          ),
        ] else ...[
          const SizedBox(height: 28),
          SectionHeader(
            title: 'Favorites',
            subtitle: favorites.isEmpty ? 'Tap the star on any item to pin it here.' : 'The things you look for most.',
            count: favorites.length,
            action: favorites.length > _previewCount ? TextButton(onPressed: onShowFavorites, child: const Text('See all')) : null,
          ),
          if (favorites.isEmpty)
            const _Hint(icon: Icons.star_outline_rounded, text: 'No favorites yet.')
          else
            ...favorites.take(_previewCount).map(actions.card),
          const SizedBox(height: 28),
          SectionHeader(title: 'Browse by category', subtitle: 'Tap a category to see everything in it.', count: categories.length),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final category in categories)
              ActionChip(
                avatar: Icon(category.category.isEmpty ? Icons.label_off_outlined : Icons.label_outline, size: 18),
                label: Text('${category.label}  ${category.count}'),
                onPressed: () => onShowCategory(category.category),
              ),
          ]),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeader(title: 'Recently added', subtitle: 'The newest things in your inventory.', action: TextButton(onPressed: onShowAll, child: const Text('See all'))),
            ...recent.map(actions.card),
          ],
          if (unassigned.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeader(title: 'Needs a home', subtitle: 'Not in a room or container yet. Use "Move to…" to file them.', count: unassigned.length),
            ...unassigned.take(_previewCount * 2).map(actions.card),
          ],
        ],
      ]))),
    ]);
  }
}

class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher({required this.onTap});
  final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            Icon(Icons.search, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text('Where did I put…?', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant))),
          ]),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon; final String label; final int value; final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(margin: EdgeInsets.zero, child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(height: 10),
          Text('$value', style: theme.textTheme.headlineSmall),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
        ]),
      ),
    ));
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon; final String text;
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
      child: Row(children: [
        Icon(icon, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
      ]),
    );
  }
}
