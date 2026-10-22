import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../discover/discover_view.dart';
import '../sharing/household_home.dart';
import '../sharing/borrowed_items_page.dart';
import '../sharing/sharing_repository.dart';
import '../sharing/return_reminders.dart';
import 'item_filter.dart';
import 'location.dart';
import 'location_repository.dart';
import 'widgets.dart';

class LocationsPage extends StatefulWidget {
  const LocationsPage({
    super.key,
    required this.repository,
    required this.user,
    required this.onHouseholdChanged,
  });
  final LocationRepository repository;
  final User user;
  final ValueChanged<String> onHouseholdChanged;
  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  StreamSubscription<List<Loan>>? _loanSubscription;
  @override
  void initState() {
    super.initState();
    final id = widget.repository.householdId;
    if (id != null) {
      _loanSubscription = SharingRepository(id).loans().listen((loans) async {
        try {
          await ReturnReminders.instance.reconcile(id, loans);
        } catch (_) {
          /* Notification failure does not block inventory. */
        }
      }, onError: (Object _) {});
    }
  }

  Future<void> _accountAction(String value) async {
    if (value == 'signOut') {
      try {
        await ReturnReminders.instance.clear();
      } finally {
        await FirebaseAuth.instance.signOut();
      }
      return;
    }
    final householdId = widget.repository.householdId;
    if (householdId == null) return;
    if (value == 'household') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AccountPage(
            householdId: householdId,
            user: widget.user,
            onSelected: widget.onHouseholdChanged,
          ),
        ),
      );
    } else if (value == 'loans') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BorrowedItemsPage(repository: widget.repository),
        ),
      );
    }
  }

  static const _discoverTab = 0;
  static const _inventoryTab = 1;

  String? _selectedLocationId;
  bool _working = false;
  int _tab = _discoverTab;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _category;
  bool _favoritesOnly = false;

  // Created once so typing in the search box doesn't re-open Firestore listeners.
  late final Stream<List<StorageLocation>> _locationsStream = widget.repository
      .watchLocations();
  late final Stream<List<StoredItem>> _itemsStream = widget.repository
      .watchItems();
  late final Stream<String> _householdNameStream = widget.repository
      .watchHouseholdName();
  late final Stream<Set<String>> _favoritesStream = widget.repository
      .watchFavoriteItemIds(widget.user.uid);

  @override
  void dispose() {
    _loanSubscription?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  StorageLocation? _find(List<StorageLocation> locations, String? id) {
    for (final location in locations) {
      if (location.id == id) return location;
    }
    return null;
  }

  String _path(StorageLocation location, List<StorageLocation> locations) {
    final parent = _find(locations, location.parentId);
    return parent == null ? location.name : '${parent.name} → ${location.name}';
  }

  Future<bool> _perform(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        _showMessage(
          error
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('Invalid argument(s): ', ''),
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addItem(List<StorageLocation> locations) async {
    final initial = _find(locations, _selectedLocationId)?.id;
    final item = await showDialog<_NewItem>(
      context: context,
      builder: (context) => _AddItemDialog(
        locations: locations,
        path: _path,
        initialLocationId: initial,
      ),
    );
    if (item == null) return;
    final added = await _perform(
      () => widget.repository.addItem(
        name: item.name,
        category: item.category,
        notes: item.notes,
        locationId: item.locationId,
      ),
    );
    if (added && mounted) _showMessage('Added ${item.name}.');
  }

  Future<void> _deleteItem(StoredItem item, {bool wasFavorite = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('Delete ${item.name}?'),
        content: const Text(
          'This removes the item from your household inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _perform(() => widget.repository.deleteItem(item));
    // Tidy up this user's star; a failure here is harmless because stale favorites are never shown.
    if (deleted && wasFavorite) {
      unawaited(
        widget.repository
            .setFavorite(widget.user.uid, item, false)
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _toggleFavorite(StoredItem item, bool isFavorite) async {
    try {
      await widget.repository.setFavorite(widget.user.uid, item, !isFavorite);
    } catch (error) {
      if (mounted) {
        _showMessage('Could not update favorites: $error', error: true);
      }
    }
  }

  Future<void> _moveItem(
    StoredItem item,
    List<StorageLocation> locations,
  ) async {
    final choice = await showDialog<({String? id})>(
      context: context,
      builder: (context) => _MoveItemDialog(
        item: item,
        locations: _ordered(locations),
        path: _path,
      ),
    );
    if (choice == null || choice.id == item.locationId) return;
    await _perform(() => widget.repository.moveItem(item, choice.id));
  }

  Future<void> _nameDialog({
    required String title,
    required String label,
    required Future<void> Function(String) submit,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value?.isNotEmpty == true) await _perform(() => submit(value!));
  }

  Future<void> _delete(StorageLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('Delete ${location.name}?'),
        content: const Text(
          'You can only delete an empty location. Items and nested containers must be moved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _perform(() async {
        await widget.repository.delete(location);
        if (_selectedLocationId == location.id && mounted) {
          setState(() => _selectedLocationId = null);
        }
      });
    }
  }

  void _showMessage(String message, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? scheme.error : null,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? scheme.onError : scheme.onInverseSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: error ? scheme.onError : scheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Display order only: each room followed by its containers, then any containers whose room is missing.
  List<StorageLocation> _ordered(List<StorageLocation> locations) {
    final rooms = locations.where((location) => location.isRoom).toList();
    final roomIds = rooms.map((room) => room.id).toSet();
    return [
      for (final room in rooms) ...[
        room,
        ...locations.where(
          (location) => !location.isRoom && location.parentId == room.id,
        ),
      ],
      ...locations.where(
        (location) => !location.isRoom && !roomIds.contains(location.parentId),
      ),
    ];
  }

  bool get _filtersActive =>
      _search.text.trim().isNotEmpty || _category != null || _favoritesOnly;

  void _clearFilters() => setState(() {
    _search.clear();
    _category = null;
    _favoritesOnly = false;
  });

  /// Switches to Inventory with the given filters. The search text is kept.
  void _openInventory({
    String? category,
    bool favoritesOnly = false,
    bool focusSearch = false,
  }) {
    setState(() {
      _tab = _inventoryTab;
      _category = category;
      _favoritesOnly = favoritesOnly;
      _selectedLocationId = null;
    });
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String>(
    stream: _householdNameStream,
    builder: (context, snapshot) =>
        _buildContent(snapshot.data ?? 'My household'),
  );

  Widget _buildContent(
    String householdName,
  ) => StreamBuilder<List<StorageLocation>>(
    stream: _locationsStream,
    builder: (context, locationsSnapshot) {
      if (locationsSnapshot.hasError) {
        return _Failure(
          message: 'Could not load locations: ${locationsSnapshot.error}',
        );
      }
      return StreamBuilder<List<StoredItem>>(
        stream: _itemsStream,
        builder: (context, itemsSnapshot) {
          if (itemsSnapshot.hasError) {
            return _Failure(
              message: 'Could not load items: ${itemsSnapshot.error}',
            );
          }
          // A favorites error only hides stars; it never blocks the inventory.
          return StreamBuilder<Set<String>>(
            stream: _favoritesStream,
            builder: (context, favoritesSnapshot) => _scaffold(
              householdName: householdName,
              locations: locationsSnapshot.data ?? const <StorageLocation>[],
              items: itemsSnapshot.data ?? const <StoredItem>[],
              favoriteIds: favoritesSnapshot.data ?? const <String>{},
              loading: !locationsSnapshot.hasData || !itemsSnapshot.hasData,
            ),
          );
        },
      );
    },
  );

  Widget _scaffold({
    required String householdName,
    required List<StorageLocation> locations,
    required List<StoredItem> items,
    required Set<String> favoriteIds,
    required bool loading,
  }) {
    final selected = _find(locations, _selectedLocationId);
    String? locationLabel(StoredItem item) {
      final location = _find(locations, item.locationId);
      return location == null ? null : _path(location, locations);
    }

    // Favorites can outlive deleted items, so only count stars on items that exist.
    final liveFavorites = {
      for (final item in items)
        if (favoriteIds.contains(item.id)) item.id,
    };
    final actions = ItemActions(
      working: _working,
      locationLabel: locationLabel,
      isFavorite: (item) => liveFavorites.contains(item.id),
      toggleFavorite: (item) =>
          _toggleFavorite(item, liveFavorites.contains(item.id)),
      move: (item) => _moveItem(item, locations),
      delete: (item) =>
          _deleteItem(item, wasFavorite: liveFavorites.contains(item.id)),
      filterCategory: (category) => setState(() {
        _tab = _inventoryTab;
        _category = category;
      }),
    );
    final inLocation = selected == null
        ? items
        : items.where((item) => item.locationId == selected.id).toList();
    final visibleItems = filterItems(
      inLocation,
      query: _search.text,
      category: _category,
      favoritesOnly: _favoritesOnly,
      favoriteIds: liveFavorites,
      locationLabel: (item) => locationLabel(item) ?? 'Unassigned',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final Widget body;
        if (_tab == _discoverTab) {
          body = DiscoverView(
            items: items,
            locationCount: locations.length,
            favoriteIds: liveFavorites,
            actions: actions,
            onSearch: () => _openInventory(focusSearch: true),
            onShowAll: () {
              _clearFilters();
              _openInventory();
            },
            onShowFavorites: () => _openInventory(favoritesOnly: true),
            onShowCategory: (category) => _openInventory(category: category),
            onShowLocations: () {
              _clearFilters();
              _openInventory();
            },
            onAddItem: () => _addItem(locations),
          );
        } else {
          final locationsPane = _LocationsPane(
            locations: _ordered(locations),
            allLocations: locations,
            items: items,
            selectedId: selected?.id,
            onSelect: (id) => setState(
              () => _selectedLocationId = id == _selectedLocationId ? null : id,
            ),
            onAddContainer: (location) => _nameDialog(
              title: 'New container',
              label: 'Container name',
              submit: (name) =>
                  widget.repository.createContainer(name, location.id),
            ),
            onRename: (location) => _nameDialog(
              title: 'Rename location',
              label: 'Name',
              initialValue: location.name,
              submit: (name) => widget.repository.rename(location, name),
            ),
            onDelete: _delete,
          );
          final itemsPane = _ItemsPane(
            selected: selected,
            locations: locations,
            items: visibleItems,
            totalCount: inLocation.length,
            path: _path,
            actions: actions,
            onAdd: () => _addItem(locations),
            search: _search,
            searchFocus: _searchFocus,
            onSearchChanged: () => setState(() {}),
            categories: categoryCounts(items),
            category: _category,
            onCategory: (category) => setState(() => _category = category),
            favoritesOnly: _favoritesOnly,
            onFavoritesOnly: (value) => setState(() => _favoritesOnly = value),
            filtersActive: _filtersActive,
            onClearFilters: _clearFilters,
            onClearLocation: () => setState(() => _selectedLocationId = null),
          );
          body = wide
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: (constraints.maxWidth * 0.36)
                              .clamp(320.0, 440.0)
                              .toDouble(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 16, 16, 96),
                            children: [locationsPane],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 24, 96),
                            children: [itemsPane],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    itemsPane,
                    const SizedBox(height: 28),
                    locationsPane,
                  ],
                );
        }

        void selectTab(int tab) => setState(() => _tab = tab);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                const _AppMark(size: 36),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(householdName, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            actions: [
              const ThemeToggleButton(),
              _AccountMenu(user: widget.user, onSelected: _accountAction),
              const SizedBox(width: 8),
            ],
            bottom: loading || _working
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                : null,
          ),
          floatingActionButton: _tab == _inventoryTab
              ? FloatingActionButton.extended(
                  onPressed: _working
                      ? null
                      : () => _nameDialog(
                          title: 'New room',
                          label: 'Room name',
                          submit: widget.repository.createRoom,
                        ),
                  icon: const Icon(Icons.add_home_outlined),
                  label: const Text('Add room'),
                )
              : FloatingActionButton.extended(
                  onPressed: _working ? null : () => _addItem(locations),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: selectTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: 'Discover',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: 'Inventory',
                    ),
                  ],
                ),
          body: SafeArea(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _tab,
                        onDestinationSelected: selectTab,
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.explore_outlined),
                            selectedIcon: Icon(Icons.explore),
                            label: Text('Discover'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.inventory_2_outlined),
                            selectedIcon: Icon(Icons.inventory_2),
                            label: Text('Inventory'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
          ),
        );
      },
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.55,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.user, required this.onSelected});
  final User user;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label =
        (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!
                : user.email ?? '?')
            .trim();
    final initial = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'account',
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user.displayName ?? 'Signed in'),
            subtitle: user.email == null ? null : Text(user.email!),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'household',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.group_outlined),
            title: Text('Account & household'),
          ),
        ),
        const PopupMenuItem(
          value: 'loans',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.handshake_outlined),
            title: Text('Borrowed items'),
          ),
        ),
        const PopupMenuItem(
          value: 'signOut',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: scheme.tertiaryContainer,
          foregroundColor: scheme.onTertiaryContainer,
          child: Text(
            initial,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _LocationsPane extends StatelessWidget {
  const _LocationsPane({
    required this.locations,
    required this.allLocations,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.onAddContainer,
    required this.onRename,
    required this.onDelete,
  });
  final List<StorageLocation> locations;
  final List<StorageLocation> allLocations;
  final List<StoredItem> items;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<StorageLocation> onAddContainer;
  final ValueChanged<StorageLocation> onRename;
  final ValueChanged<StorageLocation> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'Storage locations',
          subtitle: 'Organize rooms and the containers inside them.',
          count: locations.length,
        ),
        if (locations.isEmpty)
          const EmptyState(
            icon: Icons.meeting_room_outlined,
            title: 'No rooms yet',
            detail: 'Tap "Add room" to start organizing your household.',
          )
        else ...[
          Card(
            child: ListTile(
              selected: selectedId == null,
              onTap: () => onSelect(null),
              leading: IconTile(
                icon: Icons.apps_rounded,
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
              title: const Text('All items'),
              subtitle: const Text('Everything in your household'),
              trailing: CountPill(
                count: items.length,
                highlighted: selectedId == null,
              ),
            ),
          ),
          ...locations.map((location) {
            final count = items
                .where((item) => item.locationId == location.id)
                .length;
            StorageLocation? parent;
            if (!location.isRoom) {
              for (final other in allLocations) {
                if (other.id == location.parentId) {
                  parent = other;
                  break;
                }
              }
            }
            final isSelected = location.id == selectedId;
            return Padding(
              padding: EdgeInsets.only(left: location.isRoom ? 0 : 24),
              child: Card(
                child: ListTile(
                  selected: isSelected,
                  onTap: () => onSelect(location.id),
                  leading: location.isRoom
                      ? IconTile(
                          icon: Icons.door_front_door_outlined,
                          background: scheme.secondaryContainer,
                          foreground: scheme.onSecondaryContainer,
                        )
                      : IconTile(
                          icon: Icons.inventory_2_outlined,
                          background: scheme.tertiaryContainer,
                          foreground: scheme.onTertiaryContainer,
                        ),
                  title: Text(location.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    parent == null
                        ? (location.isRoom ? 'Room' : 'Container')
                        : 'Container in ${parent.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountPill(count: count, highlighted: isSelected),
                      PopupMenuButton<String>(
                        tooltip: 'Location options',
                        onSelected: (value) {
                          if (value == 'container') onAddContainer(location);
                          if (value == 'rename') onRename(location);
                          if (value == 'delete') onDelete(location);
                        },
                        itemBuilder: (context) => [
                          if (location.isRoom)
                            const PopupMenuItem(
                              value: 'container',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.add_box_outlined),
                                title: Text('Add container'),
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Rename'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _ItemsPane extends StatelessWidget {
  const _ItemsPane({
    required this.selected,
    required this.locations,
    required this.items,
    required this.totalCount,
    required this.path,
    required this.actions,
    required this.onAdd,
    required this.search,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.favoritesOnly,
    required this.onFavoritesOnly,
    required this.filtersActive,
    required this.onClearFilters,
    required this.onClearLocation,
  });
  final StorageLocation? selected;
  final List<StorageLocation> locations;
  final List<StoredItem> items;
  final int totalCount;
  final String Function(StorageLocation, List<StorageLocation>) path;
  final ItemActions actions;
  final VoidCallback onAdd;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onSearchChanged;
  final List<CategoryCount> categories;
  final String? category;
  final ValueChanged<String?> onCategory;
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesOnly;
  final bool filtersActive;
  final VoidCallback onClearFilters;
  final VoidCallback onClearLocation;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final category = this.category;
    final selectedKey = category == null ? null : normalizeCategory(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: selected == null ? 'All items' : path(selected, locations),
          subtitle: filtersActive
              ? 'Showing ${items.length} of $totalCount.'
              : (selected == null
                    ? 'Search, filter, or use the menu on an item to move it.'
                    : 'Only items stored here are shown.'),
          count: items.length,
          action: FilledButton.tonalIcon(
            onPressed: actions.working ? null : onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
        TextField(
          controller: search,
          focusNode: searchFocus,
          textInputAction: TextInputAction.search,
          onChanged: (_) => onSearchChanged(),
          decoration: InputDecoration(
            hintText: 'Search names, categories, notes, places',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      search.clear();
                      onSearchChanged();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.place_outlined, size: 18),
                    label: Text(selected.name),
                    tooltip: 'Show items from every location',
                    onDeleted: onClearLocation,
                  ),
                ),
              FilterChip(
                avatar: Icon(
                  favoritesOnly
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 18,
                ),
                label: const Text('Favorites'),
                selected: favoritesOnly,
                showCheckmark: false,
                onSelected: onFavoritesOnly,
              ),
              for (final option in categories)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text('${option.label}  ${option.count}'),
                    selected: selectedKey == normalizeCategory(option.category),
                    onSelected: (on) => onCategory(on ? option.category : null),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          filtersActive
              ? EmptyState(
                  icon: Icons.search_off,
                  title: 'No matches',
                  detail: 'Try a different search or clear the filters.',
                  action: TextButton.icon(
                    onPressed: onClearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Clear filters'),
                  ),
                )
              : EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No items to show',
                  detail: selected == null
                      ? 'Tap "Add item" to record where something is stored.'
                      : 'Tap "Add item" to store something here.',
                ),
        ...items.map(actions.card),
      ],
    );
  }
}

class _MoveItemDialog extends StatelessWidget {
  const _MoveItemDialog({
    required this.item,
    required this.locations,
    required this.path,
  });
  final StoredItem item;
  final List<StorageLocation> locations;
  final String Function(StorageLocation, List<StorageLocation>) path;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(
      String? id,
      String label,
      IconData icon, {
      bool indented = false,
    }) {
      final isCurrent = id == item.locationId;
      return ListTile(
        contentPadding: EdgeInsets.only(left: indented ? 48 : 24, right: 24),
        leading: Icon(icon, color: isCurrent ? scheme.primary : null),
        title: Text(label, overflow: TextOverflow.ellipsis),
        trailing: isCurrent ? Icon(Icons.check, color: scheme.primary) : null,
        selected: isCurrent,
        selectedTileColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        onTap: () => Navigator.pop(context, (id: id)),
      );
    }

    return AlertDialog(
      title: Text('Move ${item.name}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 400,
        child: ListView(
          shrinkWrap: true,
          children: [
            option(null, 'Unassigned', Icons.help_outline),
            ...locations.map(
              (location) => option(
                location.id,
                location.name,
                location.isRoom
                    ? Icons.door_front_door_outlined
                    : Icons.inventory_2_outlined,
                indented: !location.isRoom,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _NewItem {
  const _NewItem({
    required this.name,
    required this.category,
    required this.notes,
    required this.locationId,
  });
  final String name;
  final String category;
  final String notes;
  final String? locationId;
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.locations,
    required this.path,
    this.initialLocationId,
  });
  final List<StorageLocation> locations;
  final String Function(StorageLocation, List<StorageLocation>) path;
  final String? initialLocationId;
  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  late String? _locationId = widget.initialLocationId;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;
  void _save() {
    if (_canSave) {
      Navigator.pop(
        context,
        _NewItem(
          name: _name.text.trim(),
          category: _category.text.trim(),
          notes: _notes.text.trim(),
          locationId: _locationId,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.add_box_outlined),
    title: const Text('New item'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item name',
                prefixIcon: Icon(Icons.sell_outlined),
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                hintText: 'e.g. Tools, Documents',
                prefixIcon: Icon(Icons.category_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _locationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Unassigned'),
                ),
                ...widget.locations.map(
                  (location) => DropdownMenuItem<String?>(
                    value: location.id,
                    child: Text(
                      widget.path(location, widget.locations),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (id) => setState(() => _locationId = id),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _canSave ? _save : null,
        child: const Text('Add'),
      ),
    ],
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
