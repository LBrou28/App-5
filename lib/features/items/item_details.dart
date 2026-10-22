import 'package:flutter/material.dart';

import '../locations/location.dart';
import '../locations/location_repository.dart';
import 'item_editor.dart';

class ItemDetailsDialog extends StatefulWidget {
  const ItemDetailsDialog({
    super.key,
    required this.repository,
    required this.item,
    required this.locations,
  });
  final LocationRepository repository;
  final StoredItem item;
  final List<StorageLocation> locations;
  @override
  State<ItemDetailsDialog> createState() => _ItemDetailsDialogState();
}

class _ItemDetailsDialogState extends State<ItemDetailsDialog> {
  late final _items = widget.repository.watchItems();
  late final _locations = widget.repository.watchLocations();
  @override
  Widget build(BuildContext context) => StreamBuilder<List<StoredItem>>(
    stream: _items,
    initialData: [widget.item],
    builder: (context, snapshot) {
      final matches =
          snapshot.data?.where((i) => i.id == widget.item.id).toList() ?? [];
      final item = matches.isEmpty ? null : matches.first;
      return StreamBuilder<List<StorageLocation>>(
        stream: _locations,
        initialData: widget.locations,
        builder: (context, locationsSnapshot) {
          final locations = locationsSnapshot.data ?? widget.locations;
          final matches = locations.where((l) => l.id == item?.locationId);
          final location = matches.isEmpty ? null : matches.first;
          final parents = locations.where((l) => l.id == location?.parentId);
          final path = location == null
              ? 'Unassigned'
              : parents.isEmpty
              ? location.name
              : '${parents.first.name} → ${location.name}';
          final failed = snapshot.hasError || locationsSnapshot.hasError;
          return AlertDialog(
            title: Text(item?.name ?? 'Item removed'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: failed
                    ? const Text(
                        'Could not refresh this item. Close it and try again.',
                      )
                    : item == null
                    ? const Text('This item was deleted from your household.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.photoPath != null)
                            ItemPhoto(
                              repository: widget.repository,
                              path: item.photoPath!,
                            ),
                          Text('Location: $path'),
                          Text(
                            'Category: ${item.category.isEmpty ? 'None' : item.category}',
                          ),
                          Text(
                            'Borrowing status: ${item.isOnLoan ? 'On loan' : 'Available'}',
                          ),
                          if (item.notes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(item.notes),
                            ),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (item != null && !failed)
                FilledButton(
                  onPressed: () => Navigator.pop(context, item),
                  child: const Text('Edit'),
                ),
            ],
          );
        },
      );
    },
  );
}
