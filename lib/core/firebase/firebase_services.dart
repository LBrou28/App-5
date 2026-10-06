import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Initialize after flutterfire configure supplies real FirebaseOptions.
/// The default Flutter starter does not initialize Firebase until configured.
class FirebaseServices {
  FirebaseServices._();
  static Future<FirebaseServices> initialize(FirebaseOptions options) async {
    await Firebase.initializeApp(options: options);
    return FirebaseServices._();
  }

  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get database => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;
  FirebaseFunctions get functions => FirebaseFunctions.instance;

  Future<void> useEmulators({String host = 'localhost'}) async {
    await auth.useAuthEmulator(host, 9099);
    database.useFirestoreEmulator(host, 8080);
    storage.useStorageEmulator(host, 9199);
    functions.useFunctionsEmulator(host, 5001);
  }
}
