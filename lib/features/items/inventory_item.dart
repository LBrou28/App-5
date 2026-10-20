/// An item belonging to a household. Location assignment is handled separately.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    this.notes = '',
    this.locationId,
  });

  final String id;
  final String name;
  final String category;
  final String notes;
  final String? locationId;
}
