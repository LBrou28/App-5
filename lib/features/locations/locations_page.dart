import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'location.dart';
import '../items/item_editor.dart';
import '../items/item_details.dart';
import 'location_repository.dart';

class LocationsPage extends StatefulWidget {
  const LocationsPage({
    super.key,
    required this.repository,
    required this.user,
    this.onHouseholdChanged,
  });
  final LocationRepository repository;
  final User user;
  final ValueChanged<String>? onHouseholdChanged;
  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  String? _selectedLocationId;
  bool _working = false;

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
    if (_working) return false;
    setState(() => _working = true);
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is FirebaseFunctionsException
              ? error.message ?? 'Could not complete this change.'
              : 'Could not complete this change. Check your connection and try again.',
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _invite() async {
    await _perform(() async {
      final code = await widget.repository.createInvitation();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite a household member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share this code with one person. It expires in 24 hours and can be used once.',
              ),
              const SizedBox(height: 16),
              SelectableText(code),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _join() async {
    var enteredCode = '';
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a household'),
        content: TextField(
          onChanged: (value) => enteredCode = value,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Invitation code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredCode.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _perform(() async {
      final id = await widget.repository.joinHousehold(code);
      if (mounted) widget.onHouseholdChanged?.call(id);
    });
  }

  Future<void> _addItem(List<StorageLocation> locations) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemEditor(
        repository: widget.repository,
        locations: locations,
        initialLocationId: _selectedLocationId,
      ),
    );
  }

  Future<void> _details(
    StoredItem item,
    List<StorageLocation> locations,
  ) async {
    final editableItem = await showDialog<StoredItem>(
      context: context,
      builder: (context) => ItemDetailsDialog(
        repository: widget.repository,
        item: item,
        locations: locations,
      ),
    );
    if (editableItem != null && mounted) {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ItemEditor(
          repository: widget.repository,
          locations: locations,
          existing: editableItem,
        ),
      );
    }
  }

  Future<void> _deleteItem(StoredItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
    if (confirmed == true) {
      await _perform(() => widget.repository.deleteItem(item));
    }
  }

  Future<void> _nameDialog({
    required String title,
    required String label,
    required Future<void> Function(String) submit,
    String? initialValue,
  }) async {
    var enteredName = initialValue ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          onChanged: (value) => enteredName = value,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredName.trim()),
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

  void _showMessage(String message, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<StorageLocation>>(
    stream: widget.repository.watchLocations(),
    builder: (context, locationsSnapshot) {
      if (locationsSnapshot.hasError) {
        return _Failure(
          message: 'Could not load locations: ${locationsSnapshot.error}',
        );
      }
      if (!locationsSnapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final locations = locationsSnapshot.data ?? const <StorageLocation>[];
      final selected = _find(locations, _selectedLocationId);
      return StreamBuilder<List<StoredItem>>(
        stream: widget.repository.watchItems(),
        builder: (context, itemsSnapshot) {
          if (itemsSnapshot.hasError) {
            return _Failure(
              message: 'Could not load items: ${itemsSnapshot.error}',
            );
          }
          if (!itemsSnapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final items = itemsSnapshot.data ?? const <StoredItem>[];
          final visibleItems = selected == null
              ? items
              : items.where((item) => item.locationId == selected.id).toList();
          return Scaffold(
            appBar: AppBar(
              title: StreamBuilder<String>(
                stream: widget.repository.watchHouseholdName(),
                builder: (context, snapshot) =>
                    Text(snapshot.data ?? 'My household'),
              ),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Account and household',
                  enabled: !_working,
                  onSelected: (value) {
                    if (value == 'signOut') FirebaseAuth.instance.signOut();
                    if (value == 'invite') _invite();
                    if (value == 'join') _join();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'account',
                      enabled: false,
                      child: Text(widget.user.email ?? 'Signed in'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'invite',
                      child: Text('Invite a member'),
                    ),
                    if (widget.onHouseholdChanged != null)
                      const PopupMenuItem(
                        value: 'join',
                        child: Text('Join a household'),
                      ),
                    const PopupMenuItem(
                      value: 'signOut',
                      child: Text('Sign out'),
                    ),
                  ],
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _working
                  ? null
                  : () => _nameDialog(
                      title: 'New room',
                      label: 'Room name',
                      submit: widget.repository.createRoom,
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Add room'),
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final locationsPane = _LocationsPane(
                    locations: locations,
                    items: items,
                    selectedId: _selectedLocationId,
                    path: _path,
                    onSelect: (id) => setState(() => _selectedLocationId = id),
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
                      submit: (name) =>
                          widget.repository.rename(location, name),
                    ),
                    onDelete: _delete,
                  );
                  final itemsPane = _ItemsPane(
                    selected: selected,
                    locations: locations,
                    items: visibleItems,
                    path: _path,
                    working: _working,
                    onAdd: () => _addItem(locations),
                    onDelete: _deleteItem,
                    onOpen: (item) => _details(item, locations),
                    onMove: (item, destination) => _perform(
                      () => widget.repository.moveItem(item, destination),
                    ),
                  );
                  if (constraints.maxWidth >= 760) {
                    return Row(
                      children: [
                        Expanded(child: locationsPane),
                        const VerticalDivider(width: 1),
                        Expanded(child: itemsPane),
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      locationsPane,
                      const SizedBox(height: 24),
                      itemsPane,
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );
}

class _LocationsPane extends StatelessWidget {
  const _LocationsPane({
    required this.locations,
    required this.items,
    required this.selectedId,
    required this.path,
    required this.onSelect,
    required this.onAddContainer,
    required this.onRename,
    required this.onDelete,
  });
  final List<StorageLocation> locations;
  final List<StoredItem> items;
  final String? selectedId;
  final String Function(StorageLocation, List<StorageLocation>) path;
  final ValueChanged<String> onSelect;
  final ValueChanged<StorageLocation> onAddContainer;
  final ValueChanged<StorageLocation> onRename;
  final ValueChanged<StorageLocation> onDelete;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Storage locations', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Organize rooms and the containers inside them.'),
      const SizedBox(height: 12),
      if (locations.isEmpty)
        const _EmptyState(
          icon: Icons.meeting_room_outlined,
          title: 'No rooms yet',
          detail: 'Add a room to start organizing your household.',
        ),
      ...locations.map((location) {
        final count = items
            .where((item) => item.locationId == location.id)
            .length;
        return Card(
          child: ListTile(
            selected: location.id == selectedId,
            onTap: () => onSelect(location.id),
            leading: Icon(
              location.isRoom
                  ? Icons.door_front_door_outlined
                  : Icons.inventory_2_outlined,
            ),
            title: Text(path(location, locations)),
            subtitle: Text('$count ${count == 1 ? 'item' : 'items'}'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'container') onAddContainer(location);
                if (value == 'rename') onRename(location);
                if (value == 'delete') onDelete(location);
              },
              itemBuilder: (context) => [
                if (location.isRoom)
                  const PopupMenuItem(
                    value: 'container',
                    child: Text('Add container'),
                  ),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        );
      }),
    ],
  );
}

class _ItemsPane extends StatelessWidget {
  const _ItemsPane({
    required this.selected,
    required this.locations,
    required this.items,
    required this.path,
    required this.working,
    required this.onAdd,
    required this.onDelete,
    required this.onOpen,
    required this.onMove,
  });
  final StorageLocation? selected;
  final List<StorageLocation> locations;
  final List<StoredItem> items;
  final String Function(StorageLocation, List<StorageLocation>) path;
  final bool working;
  final VoidCallback onAdd;
  final ValueChanged<StoredItem> onDelete;
  final ValueChanged<StoredItem> onOpen;
  final void Function(StoredItem, String?) onMove;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              selected == null
                  ? 'All items'
                  : 'Items in ${path(selected!, locations)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: working ? null : onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        selected == null
            ? 'Move an item by choosing a new location.'
            : 'Only items stored here are shown.',
      ),
      const SizedBox(height: 12),
      if (items.isEmpty)
        _EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No items to show',
          detail: selected == null
              ? 'Tap "Add item" to record where something is stored.'
              : 'Tap "Add item" to store something here.',
        ),
      ...items.map((item) {
        StorageLocation? current;
        for (final location in locations) {
          if (location.id == item.locationId) {
            current = location;
            break;
          }
        }
        final details = [
          current == null
              ? 'Unassigned'
              : 'Stored in ${path(current, locations)}',
          if (item.category.isNotEmpty) item.category,
          if (item.isOnLoan) 'On loan',
        ].join(' · ');
        return Card(
          child: ListTile(
            onTap: working ? null : () => onOpen(item),
            leading: Icon(
              item.photoPath == null
                  ? Icons.sell_outlined
                  : Icons.photo_outlined,
            ),
            title: Text(item.name),
            subtitle: Text(
              item.notes.isEmpty ? details : '$details\n${item.notes}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: item.notes.isNotEmpty,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String?>(
                  value: current?.id,
                  underline: const SizedBox.shrink(),
                  hint: const Text('Move'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...locations.map(
                      (location) => DropdownMenuItem(
                        value: location.id,
                        child: Text(path(location, locations)),
                      ),
                    ),
                  ],
                  onChanged: working ? null : (id) => onMove(item, id),
                ),
                IconButton(
                  tooltip: 'Delete item',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: working ? null : () => onDelete(item),
                ),
              ],
            ),
          ),
        );
      }),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );
}
