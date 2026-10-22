import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'location.dart';

/// Household reads are live; shared mutations are validated on the server.
class LocationRepository {
  LocationRepository.firebase(this.householdId, {FirebaseFirestore? database})
    : _database = database ?? FirebaseFirestore.instance;

  final String householdId;
  final FirebaseFirestore _database;
  DocumentReference<Map<String, dynamic>> get _household =>
      _database.collection('households').doc(householdId);

  static Future<LocationRepository> forUser(
    String uid, {
    FirebaseFirestore? database,
  }) async {
    final db = database ?? FirebaseFirestore.instance;
    final data = (await db.collection('users').doc(uid).get()).data();
    final ids = List<String>.from(data?['householdIds'] ?? const []);
    if (ids.isNotEmpty) {
      return LocationRepository.firebase(
        data?['activeHouseholdId'] as String? ?? ids.first,
        database: db,
      );
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('createHousehold')
        .call({'name': 'My household'});
    return LocationRepository.firebase(
      result.data['householdId'] as String,
      database: db,
    );
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    await FirebaseFunctions.instance.httpsCallable(name).call({
      'householdId': householdId,
      ...data,
    });
  }

  Stream<List<StorageLocation>> watchLocations() => _household
      .collection('locations')
      .orderBy('name')
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) {
          final d = doc.data();
          return StorageLocation(
            id: doc.id,
            name: d['name'] as String? ?? 'Unnamed location',
            kind: d['kind'] == 'container'
                ? LocationKind.container
                : LocationKind.room,
            parentId: d['parentId'] as String?,
          );
        }).toList(),
      );

  Stream<String> watchHouseholdName() => _household.snapshots().map(
    (s) => s.data()?['name'] as String? ?? 'My household',
  );

  Stream<List<StoredItem>> watchItems() => _household
      .collection('items')
      .orderBy('name')
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) {
          final d = doc.data();
          return StoredItem(
            id: doc.id,
            name: d['name'] as String? ?? 'Unnamed item',
            locationId: d['locationId'] as String?,
            category: d['category'] as String? ?? '',
            notes: d['notes'] as String? ?? '',
            activeLoanId: d['activeLoanId'] as String?,
            photoPath: d['photoPath'] as String?,
            revision: d['revision'] as int? ?? 0,
          );
        }).toList(),
      );

  Future<String> createInvitation() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('createHouseholdInvite')
        .call({'householdId': householdId});
    return result.data['code'] as String;
  }

  Future<String> joinHousehold(String code) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('joinHousehold')
        .call({'code': code.trim()});
    return result.data['householdId'] as String;
  }

  Future<void> createRoom(String name) =>
      _call('createLocation', {'name': name, 'kind': 'room'});
  Future<void> createContainer(String name, String roomId) => _call(
    'createLocation',
    {'name': name, 'kind': 'container', 'parentId': roomId},
  );
  Future<void> rename(StorageLocation location, String name) =>
      _call('renameLocation', {'locationId': location.id, 'name': name});
  Future<void> delete(StorageLocation location) =>
      _call('deleteLocation', {'locationId': location.id});
  Future<void> moveItem(StoredItem item, String? locationId) =>
      _call('moveItem', {'itemId': item.id, 'locationId': locationId});
  Future<void> deleteItem(StoredItem item) =>
      _call('deleteItem', {'itemId': item.id});

  Future<Uint8List?> loadPhoto(String path) =>
      FirebaseStorage.instance.ref(path).getData(5 * 1024 * 1024);

  Future<void> addItem({
    required String name,
    String category = '',
    String notes = '',
    String? locationId,
  }) => saveItem(
    name: name,
    category: category,
    notes: notes,
    locationId: locationId,
  );

  String newItemId() => _household.collection('items').doc().id;

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
    final itemId = existing?.id ?? draftId ?? newItemId();
    String? uploadedPath;
    if (photo != null) {
      if (photo.length >= 5 * 1024 * 1024) {
        throw ArgumentError('Choose a photo smaller than 5 MB.');
      }
      uploadedPath =
          'households/$householdId/items/$itemId/${_database.collection('_ids').doc().id}';
      await FirebaseStorage.instance
          .ref(uploadedPath)
          .putData(
            photo,
            SettableMetadata(contentType: photoType ?? 'image/jpeg'),
          );
    }
    // Keep uploads after an ambiguous network response: the write may have
    // committed. A daily server job removes unreferenced uploads after 24 hours.
    await _call(existing == null ? 'createItem' : 'updateItem', {
      'revision': existing?.revision ?? 0,
      'itemId': itemId,
      'name': name,
      'category': category,
      'notes': notes,
      'locationId': locationId,
      'photoPath': uploadedPath ?? (removePhoto ? null : existing?.photoPath),
    });
  }
}
