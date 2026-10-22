import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'location.dart';

/// Spark-plan implementation: Firestore transactions keep location counters valid.
class LocationRepository {
  LocationRepository.demo()
      : _locations = [
          const StorageLocation(id: 'bedroom', name: 'Bedroom', kind: LocationKind.room),
          const StorageLocation(id: 'garage', name: 'Garage', kind: LocationKind.room),
          const StorageLocation(id: 'drawer', name: 'Top drawer', kind: LocationKind.container, parentId: 'bedroom'),
        ],
        _items = [const StoredItem(id: 'keys', name: 'Spare keys', locationId: 'drawer'), const StoredItem(id: 'hammer', name: 'Hammer', locationId: 'garage')],
        householdId = null,
        _database = null;
  LocationRepository.firebase(this.householdId, {FirebaseFirestore? database})
      : _database = database ?? FirebaseFirestore.instance,
        _locations = null,
        _items = null;

  final String? householdId;
  final FirebaseFirestore? _database;
  final List<StorageLocation>? _locations;
  final List<StoredItem>? _items;
  bool get _isDemo => _locations != null;
  DocumentReference<Map<String, dynamic>> get _household => _database!.collection('households').doc(householdId);

  static Future<LocationRepository> forUser(String uid, {FirebaseFirestore? database}) async {
    final db = database ?? FirebaseFirestore.instance;
    final user = db.collection('users').doc(uid);
    final data = (await user.get()).data();
    final ids = List<String>.from(data?['householdIds'] ?? const []);
    if (ids.isNotEmpty) return LocationRepository.firebase(ids.first, database: db);
    final household = db.collection('households').doc();
    final batch = db.batch();
    batch.set(household, {'name': 'My household', 'ownerId': uid, 'createdAt': FieldValue.serverTimestamp()});
    batch.set(household.collection('members').doc(uid), {'role': 'owner', 'joinedAt': FieldValue.serverTimestamp()});
    batch.set(user, {'householdIds': [household.id]}, SetOptions(merge: true));
    await batch.commit();
    return LocationRepository.firebase(household.id, database: db);
  }

  Stream<List<StorageLocation>> watchLocations() {
    if (_isDemo) return Stream.value(List.unmodifiable(_locations!));
    return _household.collection('locations').orderBy('name').snapshots().map((snap) => snap.docs.map((doc) {
      final d = doc.data();
      return StorageLocation(id: doc.id, name: d['name'] as String? ?? 'Unnamed location', kind: d['kind'] == 'container' ? LocationKind.container : LocationKind.room, parentId: d['parentId'] as String?);
    }).toList());
  }

  Stream<String> watchHouseholdName() {
    if (_isDemo) return Stream.value('My household');
    return _household.snapshots().map((snapshot) => snapshot.data()?['name'] as String? ?? 'My household');
  }

  Stream<List<StoredItem>> watchItems() {
    if (_isDemo) return Stream.value(List.unmodifiable(_items!));
    return _household.collection('items').orderBy('name').snapshots().map((snap) => snap.docs.map((doc) {
      final d = doc.data();
      final createdAt = d['createdAt'];
      return StoredItem(id: doc.id, name: d['name'] as String? ?? 'Unnamed item', locationId: d['locationId'] as String?, category: d['category'] as String? ?? '', notes: d['notes'] as String? ?? '', activeLoanId: d['activeLoanId'] as String?, createdAt: createdAt is Timestamp ? createdAt.toDate() : null);
    }).toList());
  }

  Future<void> createRoom(String name) => _create(name, LocationKind.room);
  Future<void> createContainer(String name, String roomId) => _create(name, LocationKind.container, parentId: roomId);
  Future<void> _create(String name, LocationKind kind, {String? parentId}) async {
    _checkName(name); if (_isDemo) return;
    final location = _household.collection('locations').doc();
    await _database!.runTransaction((tx) async {
      if (kind == LocationKind.container) {
        final parent = _household.collection('locations').doc(parentId);
        final data = (await tx.get(parent)).data();
        if (data == null || data['kind'] != 'room') throw StateError('Choose an existing room.');
        tx.update(parent, {'childCount': FieldValue.increment(1)});
      }
      tx.set(location, {'name': name.trim(), 'kind': kind.name, 'parentId': parentId, 'itemCount': 0, 'childCount': 0, 'createdAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> rename(StorageLocation location, String name) async { _checkName(name); if (!_isDemo) await _household.collection('locations').doc(location.id).update({'name': name.trim()}); }

  Future<void> delete(StorageLocation location) async {
    if (_isDemo) return;
    final ref = _household.collection('locations').doc(location.id);
    await _database!.runTransaction((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null) throw StateError('Location no longer exists.');
      if ((data['itemCount'] as int? ?? 0) != 0 || (data['childCount'] as int? ?? 0) != 0) throw StateError('Move all items and containers before deleting this location.');
      final parentId = data['parentId'] as String?;
      if (parentId != null) tx.update(_household.collection('locations').doc(parentId), {'childCount': FieldValue.increment(-1)});
      tx.delete(ref);
    });
  }

  Future<void> moveItem(StoredItem item, String? locationId) async {
    if (_isDemo) return;
    final itemRef = _household.collection('items').doc(item.id);
    await _database!.runTransaction((tx) async {
      final itemData = (await tx.get(itemRef)).data();
      if (itemData == null) throw StateError('Item no longer exists.');
      final destination = locationId == null ? null : _household.collection('locations').doc(locationId);
      if (destination != null && !(await tx.get(destination)).exists) throw StateError('Destination location no longer exists.');
      final oldId = itemData['locationId'] as String?;
      if (oldId == locationId) return;
      if (oldId != null) tx.update(_household.collection('locations').doc(oldId), {'itemCount': FieldValue.increment(-1)});
      if (destination != null) tx.update(destination, {'itemCount': FieldValue.increment(1)});
      tx.update(itemRef, {'locationId': locationId, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Creates an item and, when it is placed in a location, bumps that location's itemCount in the same transaction.
  Future<void> addItem({required String name, String category = '', String notes = '', String? locationId}) async {
    _checkName(name);
    _checkText(category, 100, 'Category');
    _checkText(notes, 2000, 'Notes');
    if (_isDemo) return;
    final itemRef = _household.collection('items').doc();
    await _database!.runTransaction((tx) async {
      if (locationId != null) {
        final destination = _household.collection('locations').doc(locationId);
        if (!(await tx.get(destination)).exists) throw StateError('Choose an existing location.');
        tx.update(destination, {'itemCount': FieldValue.increment(1)});
      }
      tx.set(itemRef, {
        'name': name.trim(),
        'category': category.trim(),
        'notes': notes.trim(),
        'locationId': locationId,
        'activeLoanId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Deletes an item that is not on loan and decrements its location's itemCount.
  Future<void> deleteItem(StoredItem item) async {
    if (_isDemo) return;
    final itemRef = _household.collection('items').doc(item.id);
    await _database!.runTransaction((tx) async {
      final data = (await tx.get(itemRef)).data();
      if (data == null) throw StateError('Item no longer exists.');
      if (data['activeLoanId'] != null) throw StateError('Return this item before deleting it.');
      final locationId = data['locationId'] as String?;
      final location = locationId == null ? null : _household.collection('locations').doc(locationId);
      if (location != null && (await tx.get(location)).exists) tx.update(location, {'itemCount': FieldValue.increment(-1)});
      tx.delete(itemRef);
    });
  }

  CollectionReference<Map<String, dynamic>> _favorites(String uid) => _database!.collection('users').doc(uid).collection('favorites');

  /// Ids of the items this user has starred in this household (users/{uid}/favorites).
  Stream<Set<String>> watchFavoriteItemIds(String uid) {
    if (_isDemo) return Stream.value(const <String>{});
    return _favorites(uid).where('householdId', isEqualTo: householdId).snapshots().map((snap) => {
      for (final doc in snap.docs)
        if (doc.data()['itemId'] is String) doc.data()['itemId'] as String,
    });
  }

  /// Stars or un-stars an item for this user. One document per household item.
  Future<void> setFavorite(String uid, StoredItem item, bool favorite) async {
    if (_isDemo) return;
    final ref = _favorites(uid).doc('${householdId}_${item.id}');
    if (favorite) {
      await ref.set({'householdId': householdId, 'itemId': item.id, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  static void _checkText(String value, int max, String label) { if (value.trim().length > max) throw ArgumentError('$label must be $max characters or fewer.'); }

  static void _checkName(String name) { if (name.trim().isEmpty || name.trim().length > 200 || name.contains('/')) throw ArgumentError('Enter a valid name.'); }
}
