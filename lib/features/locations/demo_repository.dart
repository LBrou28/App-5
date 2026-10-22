import 'dart:async';
import 'dart:typed_data';

import 'location.dart';
import 'location_repository.dart';

/// An isolated, session-only preview. Never initializes or contacts Firebase.
class DemoLocationRepository extends LocationRepository {
  DemoLocationRepository() : super.offline();
  final _changes = StreamController<void>.broadcast(sync: true);
  int _id = 0;
  final _photos = <String, Uint8List>{};
  final _locations = <StorageLocation>[
    const StorageLocation(
      id: 'bedroom',
      name: 'Bedroom',
      kind: LocationKind.room,
    ),
    const StorageLocation(
      id: 'drawer',
      name: 'Top drawer',
      kind: LocationKind.container,
      parentId: 'bedroom',
    ),
    const StorageLocation(
      id: 'garage',
      name: 'Garage',
      kind: LocationKind.room,
    ),
    const StorageLocation(
      id: 'cabinet',
      name: 'Tool cabinet',
      kind: LocationKind.container,
      parentId: 'garage',
    ),
  ];
  final _items = <StoredItem>[
    const StoredItem(
      id: 'passport',
      name: 'Passport',
      category: 'Documents',
      notes: 'Inside the blue travel folder.',
      locationId: 'drawer',
    ),
    const StoredItem(
      id: 'toolbox',
      name: 'Toolbox',
      category: 'Tools',
      notes: 'Shared tools for household repairs.',
      locationId: 'cabinet',
    ),
    const StoredItem(
      id: 'drill',
      name: 'Cordless drill',
      category: 'Tools',
      notes: 'Borrowed by Alex. Return expected Friday.',
      locationId: 'garage',
      activeLoanId: 'sample-loan',
    ),
  ];
  Stream<T> _watch<T>(T Function() read) => Stream<T>.multi((controller) {
    controller.add(read());
    final subscription = _changes.stream.listen((_) => controller.add(read()));
    controller.onCancel = subscription.cancel;
  });
  @override
  Stream<List<StorageLocation>> watchLocations() =>
      _watch(() => List.unmodifiable(_locations));
  @override
  Stream<List<StoredItem>> watchItems() =>
      _watch(() => List.unmodifiable(_items));
  @override
  Stream<String> watchHouseholdName() => Stream.value('Demo household');
  @override
  String newItemId() => 'demo-${_id++}';
  @override
  Future<Uint8List?> loadPhoto(String path) async => _photos[path];
  void _name(String name) {
    if (name.trim().isEmpty || name.trim().length > 200 || name.contains('/')) {
      throw ArgumentError('Enter a valid name.');
    }
  }

  void _location(String? id) {
    if (id != null && !_locations.any((l) => l.id == id)) {
      throw StateError('Location no longer exists.');
    }
  }

  StoredItem _current(String id) => _items.firstWhere(
    (i) => i.id == id,
    orElse: () => throw StateError('Item no longer exists.'),
  );
  @override
  Future<void> createRoom(String name) async {
    _name(name);
    _locations.add(
      StorageLocation(
        id: newItemId(),
        name: name.trim(),
        kind: LocationKind.room,
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> createContainer(String name, String roomId) async {
    _name(name);
    if (!_locations.any((l) => l.id == roomId && l.isRoom)) {
      throw StateError('Choose a room.');
    }
    _locations.add(
      StorageLocation(
        id: newItemId(),
        name: name.trim(),
        kind: LocationKind.container,
        parentId: roomId,
      ),
    );
    _changes.add(null);
  }

  @override
  Future<void> rename(StorageLocation location, String name) async {
    _name(name);
    final index = _locations.indexWhere((l) => l.id == location.id);
    if (index < 0) throw StateError('Location no longer exists.');
    _locations[index] = StorageLocation(
      id: location.id,
      name: name.trim(),
      kind: location.kind,
      parentId: location.parentId,
    );
    _changes.add(null);
  }

  @override
  Future<void> delete(StorageLocation location) async {
    if (_items.any((i) => i.locationId == location.id) ||
        _locations.any((l) => l.parentId == location.id)) {
      throw StateError(
        'Move items and containers before deleting this location.',
      );
    }
    _locations.removeWhere((l) => l.id == location.id);
    _changes.add(null);
  }

  @override
  Future<void> moveItem(StoredItem item, String? locationId) async {
    final current = _current(item.id);
    await saveItem(
      existing: current,
      name: current.name,
      category: current.category,
      notes: current.notes,
      locationId: locationId,
    );
  }

  @override
  Future<void> deleteItem(StoredItem item) async {
    final current = _current(item.id);
    if (current.isOnLoan) {
      throw StateError('Return this item before deleting it.');
    }
    _photos.remove(current.photoPath);
    _items.removeWhere((i) => i.id == item.id);
    _changes.add(null);
  }

  @override
  Future<void> saveItem({
    String? draftId,
    StoredItem? existing,
    required String name,
    required String category,
    required String notes,
    String? locationId,
    Uint8List? photo,
    String? photoType,
    bool removePhoto = false,
  }) async {
    _name(name);
    _location(locationId);
    if (category.trim().length > 100 || notes.trim().length > 2000) {
      throw ArgumentError('Item details are too long.');
    }
    final current = existing == null ? null : _current(existing.id);
    if (current != null && current.revision != existing!.revision) {
      throw StateError('Reopen the item before editing.');
    }
    final id = existing?.id ?? draftId ?? newItemId();
    if (existing == null && _items.any((i) => i.id == id)) {
      throw StateError('Item already saved.');
    }
    String? photoPath = removePhoto ? null : current?.photoPath;
    if (photo != null) {
      if (photo.length >= 5 * 1024 * 1024) {
        throw ArgumentError('Choose a photo smaller than 5 MB.');
      }
      photoPath = 'demo-photo-${newItemId()}';
      _photos[photoPath] = Uint8List.fromList(photo);
    }
    if (current?.photoPath != photoPath) _photos.remove(current?.photoPath);
    final saved = StoredItem(
      id: id,
      name: name.trim(),
      category: category.trim(),
      notes: notes.trim(),
      locationId: locationId,
      photoPath: photoPath,
      activeLoanId: current?.activeLoanId,
      revision: (current?.revision ?? 0) + 1,
    );
    _items.removeWhere((i) => i.id == id);
    _items.add(saved);
    _changes.add(null);
  }

  @override
  Future<String> createInvitation() async =>
      throw StateError('Invitations require a signed-in household.');
  @override
  Future<String> joinHousehold(String code) async =>
      throw StateError('Joining requires sign-in.');
}
