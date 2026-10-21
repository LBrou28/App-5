class StorageLocation {
  const StorageLocation({required this.id, required this.name, required this.kind, this.parentId});
  final String id;
  final String name;
  final LocationKind kind;
  final String? parentId;
  bool get isRoom => kind == LocationKind.room;
}

enum LocationKind { room, container }

class StoredItem {
  const StoredItem({required this.id, required this.name, this.locationId});
  final String id;
  final String name;
  final String? locationId;
}
