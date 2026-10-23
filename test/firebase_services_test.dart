import 'package:app_5/core/firebase/firebase_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'test accounts cannot authenticate before emulator configuration',
    () async {
      await expectLater(
        FirebaseServices.signInLocalUser('a'),
        throwsStateError,
      );
      await expectLater(
        FirebaseServices.signInLocalUser('unknown'),
        throwsStateError,
      );
    },
  );
}
