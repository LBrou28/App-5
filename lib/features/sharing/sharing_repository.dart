import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SharingRepository {
  SharingRepository(this.householdId);
  final String householdId;
  final _db = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get home =>
      _db.collection('households').doc(householdId);
  static Future<dynamic> call(String name, Map<String, dynamic> data) async =>
      (await FirebaseFunctions.instance.httpsCallable(name).call<dynamic>(data))
          .data;
  static Future<String> create(String name) async =>
      (await call('createHousehold', {'name': name}))['householdId'] as String;
  static Future<String> join(String code) async =>
      (await call('joinHousehold', {'code': code.trim()}))['householdId']
          as String;
  Future<String> invite() async =>
      (await call('createInvitation', {'householdId': householdId}))['code']
          as String;
  Future<void> leave() async {
    await call('leaveHousehold', {'householdId': householdId});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> members() =>
      home.collection('members').snapshots();
  Stream<List<Loan>> loans() => home
      .collection('loans')
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map(Loan.fromDoc).toList()
              ..sort((a, b) => b.borrowedAt.compareTo(a.borrowedAt)),
      );
  Future<String> borrow(String itemId, String borrower, DateTime due) async =>
      (await call('borrowItem', {
            'householdId': householdId,
            'itemId': itemId,
            'borrower': borrower.trim(),
            'dueDate': due.millisecondsSinceEpoch,
          }))['loanId']
          as String;
  Future<void> returnItem(String itemId) async {
    await call('returnItem', {'householdId': householdId, 'itemId': itemId});
  }
}

class Loan {
  Loan({
    required this.id,
    required this.itemId,
    required this.borrower,
    required this.recordedBy,
    required this.dueDate,
    required this.borrowedAt,
    this.returnedAt,
  });
  factory Loan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Loan(
      id: doc.id,
      itemId: d['itemId'] as String,
      borrower: d['borrower'] as String,
      recordedBy: d['recordedBy'] as String,
      dueDate: (d['dueDate'] as Timestamp).toDate(),
      borrowedAt: (d['borrowedAt'] as Timestamp).toDate(),
      returnedAt: (d['returnedAt'] as Timestamp?)?.toDate(),
    );
  }
  final String id, itemId, borrower, recordedBy;
  final DateTime dueDate, borrowedAt;
  final DateTime? returnedAt;
  bool get active => returnedAt == null;
  bool overdueAt(DateTime now) => active && dueDate.isBefore(now);
}
