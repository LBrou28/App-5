import 'package:flutter/material.dart';

import 'location.dart';

/// Shared building blocks for the Inventory and Discover screens.

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.subtitle, this.count, this.action});
  final String title; final String subtitle; final int? count; final Widget? action;
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = this.count;
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(title, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
            if (count != null) ...[const SizedBox(width: 8), CountPill(count: count)],
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ])),
        if (action != null) ...[const SizedBox(width: 12), action],
      ]),
    );
  }
}

class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.count, this.highlighted = false});
  final int count; final bool highlighted;
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: highlighted ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Text('$count', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: highlighted ? scheme.onPrimary : scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.background, required this.foreground});
  final IconData icon; final Color background; final Color foreground;
  @override Widget build(BuildContext context) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, size: 22, color: foreground),
  );
}

class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, required this.background, required this.foreground, this.icon, this.onTap, this.tooltip});
  final String label; final Color background; final Color foreground; final IconData? icon; final VoidCallback? onTap; final String? tooltip;
  @override Widget build(BuildContext context) {
    final icon = this.icon;
    final tag = Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 4)],
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
    return tooltip == null ? tag : Tooltip(message: tooltip!, child: tag);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.detail, this.action});
  final IconData icon; final String title; final String detail; final Widget? action;
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = this.action;
    return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32), child: Column(children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle), child: Icon(icon, size: 30, color: scheme.onPrimaryContainer)),
      const SizedBox(height: 16),
      Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(detail, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      if (action != null) ...[const SizedBox(height: 16), action],
    ])));
  }
}

/// Everything an item card needs to show and act on an item.
class ItemActions {
  const ItemActions({required this.working, required this.locationLabel, required this.isFavorite, required this.toggleFavorite, required this.move, required this.delete, required this.filterCategory});

  /// True while a write is in progress; menus are disabled meanwhile.
  final bool working;

  /// Readable location path for an item, or null when it has no (existing) location.
  final String? Function(StoredItem item) locationLabel;
  final bool Function(StoredItem item) isFavorite;
  final void Function(StoredItem item) toggleFavorite;
  final void Function(StoredItem item) move;
  final void Function(StoredItem item) delete;

  /// Shows every item in a category ('' for uncategorized).
  final void Function(String category) filterCategory;

  Widget card(StoredItem item) => ItemCard(key: ValueKey(item.id), item: item, actions: this);
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.actions});
  final StoredItem item; final ItemActions actions;

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final location = actions.locationLabel(item);
    final favorite = actions.isFavorite(item);
    final initial = item.name.trim().isEmpty ? '?' : item.name.trim().characters.first.toUpperCase();
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40, alignment: Alignment.center,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Text(initial, style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(children: [
            Icon(location == null ? Icons.help_outline : Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(child: Text(location ?? 'Unassigned', overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
          ]),
          if (item.category.isNotEmpty || item.isOnLoan) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (item.category.isNotEmpty) Tag(label: item.category, background: scheme.secondaryContainer, foreground: scheme.onSecondaryContainer, tooltip: 'Show all ${item.category}', onTap: () => actions.filterCategory(item.category)),
              if (item.isOnLoan) Tag(label: 'On loan', icon: Icons.schedule, background: scheme.tertiaryContainer, foreground: scheme.onTertiaryContainer),
            ]),
          ),
          if (item.notes.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(item.notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
          ),
        ])),
        IconButton(
          tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
          isSelected: favorite,
          icon: const Icon(Icons.star_border_rounded),
          selectedIcon: Icon(Icons.star_rounded, color: scheme.tertiary),
          onPressed: () => actions.toggleFavorite(item),
        ),
        PopupMenuButton<String>(
          tooltip: 'Item options',
          enabled: !actions.working,
          onSelected: (value) { if (value == 'move') actions.move(item); if (value == 'delete') actions.delete(item); },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'move', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.drive_file_move_outline), title: Text('Move to…'))),
            PopupMenuItem(value: 'delete', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline), title: Text('Delete'))),
          ],
        ),
      ]),
    ));
  }
}
