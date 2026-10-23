import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Configure all Firebase services before any feature opens a listener.
class FirebaseServices {
  FirebaseServices._();
  static const _emulatorsRequested = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static bool get emulatorsEnabled => kDebugMode && _emulatorsRequested;
  static bool _configuredForEmulators = false;
  static String get emulatorHost =>
      const String.fromEnvironment('FIREBASE_EMULATOR_HOST').isNotEmpty
      ? const String.fromEnvironment('FIREBASE_EMULATOR_HOST')
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? '10.0.2.2'
            : '127.0.0.1');

  static Future<FirebaseServices> initialize(FirebaseOptions options) async {
    if (_emulatorsRequested && !kDebugMode) {
      throw StateError('Emulator mode is only supported in debug builds.');
    }
    await Firebase.initializeApp(options: options);
    final services = FirebaseServices._();
    if (emulatorsEnabled) await services.useEmulators(host: emulatorHost);
    return services;
  }

  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get database => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;
  FirebaseFunctions get functions => FirebaseFunctions.instance;

  Future<void> useEmulators({String host = '127.0.0.1'}) async {
    await auth.useAuthEmulator(host, 9099);
    database.settings = const Settings(persistenceEnabled: false);
    database.useFirestoreEmulator(host, 8080);
    storage.useStorageEmulator(host, 9199);
    functions.useFunctionsEmulator(host, 5001);
    _configuredForEmulators = true;
  }

  /// Fake accounts let two devices rehearse sharing without Google credentials.
  static Future<void> signInLocalUser(String account) async {
    if (!emulatorsEnabled ||
        !_configuredForEmulators ||
        !['a', 'b'].contains(account)) {
      throw StateError(
        'Local test accounts require configured Firebase emulators.',
      );
    }
    final email = 'local-member-$account@example.test';
    const password = 'local-emulator-only-password';
    final auth = FirebaseAuth.instance;
    try {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found' &&
          error.code != 'invalid-credential') {
        rethrow;
      }
      await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
  }
}
