import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'location.dart';
import 'location_repository.dart';

class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key, required this.repository, required this.user});
  final LocationRepository repository;
  final User user;
  @override State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  String? _selectedLocationId;
  bool _working = false;

  StorageLocation? _find(List<StorageLocation> locations, String? id) {
    for (final location in locations) { if (location.id == id) return location; }
    return null;
  }

  String _path(StorageLocation location, List<StorageLocation> locations) {
    final parent = _find(locations, location.parentId);
    return parent == null ? location.name : '${parent.name} → ${location.name}';
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() => _working = true);
    try { await action(); }
    catch (error) { if (mounted) _showMessage(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''), error: true); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _nameDialog({required String title, required String label, required Future<void> Function(String) submit, String? initialValue}) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: label), onSubmitted: (value) => Navigator.pop(context, value.trim())),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))],
    ));
    if (value?.isNotEmpty == true) await _perform(() => submit(value!));
  }

  Future<void> _delete(StorageLocation location) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Delete ${location.name}?'),
      content: const Text('You can only delete an empty location. Items and nested containers must be moved first.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (confirmed == true) await _perform(() async { await widget.repository.delete(location); if (_selectedLocationId == location.id && mounted) setState(() => _selectedLocationId = null); });
  }

  void _showMessage(String message, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  @override Widget build(BuildContext context) => StreamBuilder<List<StorageLocation>>(
    stream: widget.repository.watchLocations(),
    builder: (context, locationsSnapshot) {
      if (locationsSnapshot.hasError) return _Failure(message: 'Could not load locations: ${locationsSnapshot.error}');
      final locations = locationsSnapshot.data ?? const <StorageLocation>[];
      final selected = _find(locations, _selectedLocationId);
      return StreamBuilder<List<StoredItem>>(
        stream: widget.repository.watchItems(),
        builder: (context, itemsSnapshot) {
          if (itemsSnapshot.hasError) return _Failure(message: 'Could not load items: ${itemsSnapshot.error}');
          final items = itemsSnapshot.data ?? const <StoredItem>[];
          final visibleItems = selected == null ? items : items.where((item) => item.locationId == selected.id).toList();
          return Scaffold(
            appBar: AppBar(
              title: StreamBuilder<String>(stream: widget.repository.watchHouseholdName(), builder: (context, snapshot) => Text(snapshot.data ?? 'My household')),
              actions: [PopupMenuButton<String>(onSelected: (value) { if (value == 'signOut') FirebaseAuth.instance.signOut(); }, itemBuilder: (context) => [PopupMenuItem(value: 'account', enabled: false, child: Text(widget.user.email ?? 'Signed in')), const PopupMenuDivider(), const PopupMenuItem(value: 'signOut', child: Text('Sign out'))])],
            ),
            floatingActionButton: FloatingActionButton.extended(onPressed: _working ? null : () => _nameDialog(title: 'New room', label: 'Room name', submit: widget.repository.createRoom), icon: const Icon(Icons.add), label: const Text('Add room')),
            body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
              final locationsPane = _LocationsPane(locations: locations, items: items, selectedId: _selectedLocationId, path: _path, onSelect: (id) => setState(() => _selectedLocationId = id), onAddContainer: (location) => _nameDialog(title: 'New container', label: 'Container name', submit: (name) => widget.repository.createContainer(name, location.id)), onRename: (location) => _nameDialog(title: 'Rename location', label: 'Name', initialValue: location.name, submit: (name) => widget.repository.rename(location, name)), onDelete: _delete);
              final itemsPane = _ItemsPane(selected: selected, locations: locations, items: visibleItems, path: _path, working: _working, onMove: (item, destination) => _perform(() => widget.repository.moveItem(item, destination)));
              if (constraints.maxWidth >= 760) return Row(children: [Expanded(child: locationsPane), const VerticalDivider(width: 1), Expanded(child: itemsPane)]);
              return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [locationsPane, const SizedBox(height: 24), itemsPane]);
            })),
          );
        },
      );
    },
  );
}

class _LocationsPane extends StatelessWidget {
  const _LocationsPane({required this.locations, required this.items, required this.selectedId, required this.path, required this.onSelect, required this.onAddContainer, required this.onRename, required this.onDelete});
  final List<StorageLocation> locations; final List<StoredItem> items; final String? selectedId; final String Function(StorageLocation, List<StorageLocation>) path; final ValueChanged<String> onSelect; final ValueChanged<StorageLocation> onAddContainer; final ValueChanged<StorageLocation> onRename; final ValueChanged<StorageLocation> onDelete;
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text('Storage locations', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 4), const Text('Organize rooms and the containers inside them.'), const SizedBox(height: 12),
    if (locations.isEmpty) const _EmptyState(icon: Icons.meeting_room_outlined, title: 'No rooms yet', detail: 'Add a room to start organizing your household.'),
    ...locations.map((location) { final count = items.where((item) => item.locationId == location.id).length; return Card(child: ListTile(selected: location.id == selectedId, onTap: () => onSelect(location.id), leading: Icon(location.isRoom ? Icons.door_front_door_outlined : Icons.inventory_2_outlined), title: Text(path(location, locations)), subtitle: Text('$count ${count == 1 ? 'item' : 'items'}'), trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'container') onAddContainer(location); if (value == 'rename') onRename(location); if (value == 'delete') onDelete(location); }, itemBuilder: (context) => [if (location.isRoom) const PopupMenuItem(value: 'container', child: Text('Add container')), const PopupMenuItem(value: 'rename', child: Text('Rename')), const PopupMenuItem(value: 'delete', child: Text('Delete'))]))); }),
  ]);
}

class _ItemsPane extends StatelessWidget {
  const _ItemsPane({required this.selected, required this.locations, required this.items, required this.path, required this.working, required this.onMove});
  final StorageLocation? selected; final List<StorageLocation> locations; final List<StoredItem> items; final String Function(StorageLocation, List<StorageLocation>) path; final bool working; final void Function(StoredItem, String?) onMove;
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text(selected == null ? 'All items' : 'Items in ${path(selected!, locations)}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 4), Text(selected == null ? 'Move an item by choosing a new location.' : 'Only items stored here are shown.'), const SizedBox(height: 12),
    if (items.isEmpty) const _EmptyState(icon: Icons.inventory_2_outlined, title: 'No items to show', detail: 'Items added by the inventory feature will appear here.'),
    ...items.map((item) {
      StorageLocation? current;
      for (final location in locations) {
        if (location.id == item.locationId) { current = location; break; }
      }
      return Card(child: ListTile(leading: const Icon(Icons.sell_outlined), title: Text(item.name), subtitle: Text(current == null ? 'Unassigned' : 'Stored in ${path(current, locations)}'), trailing: DropdownButton<String?>(value: current?.id, underline: const SizedBox.shrink(), hint: const Text('Move'), items: [const DropdownMenuItem(value: null, child: Text('Unassigned')), ...locations.map((location) => DropdownMenuItem(value: location.id, child: Text(path(location, locations))))], onChanged: working ? null : (id) => onMove(item, id))));
    }),
  ]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail});
  final IconData icon; final String title; final String detail;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4), Text(detail, textAlign: TextAlign.center)])));
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message}); final String message;
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center))));
}
