# App-5

Flutter inventory starter with a working storage-location preview. It includes rooms, nested containers, readable paths, and item-location selection. The preview uses sample data until Firebase is configured; create a `LocationRepository.firebase(householdId)` after sign-in to invoke the secured location Functions.

## Authentication and storage locations

The app initializes Firebase from `lib/firebase_options.dart`, shows a Google sign-in screen, creates a first household for a new user, and stores rooms, containers, and item locations in Firestore. Anonymous sessions are upgraded to Google credentials without losing their household data. Google sign-in is enabled in Firebase Authentication; Android builds still need their debug and release SHA-1 fingerprints registered in Firebase Project Settings before native sign-in will work.

## Run

Use Flutter 3.47.6 or newer:

```sh
flutter pub get
flutter run
```

Platform projects are included for Android, iOS, and web. Android requires Android SDK; iOS requires macOS/Xcode. For this checkout only, a local SDK is available at `.tools/flutter/bin/flutter.bat` (ignored by Git).

## Checks

```sh
flutter analyze
flutter test
```

## Retained Firebase scaffold

Firebase dependencies and `lib/core/firebase/firebase_services.dart` are available but not initialized by the starter app. Firestore/Storage rules, emulator configuration, and starter Cloud Functions are retained. No Firebase project is configured or deployed.

When ready, run `flutterfire configure` to generate real `lib/firebase_options.dart`. Initialize Firebase with those generated options before using the services. Choose the same project for Firebase CLI using `firebase use --add`.

The `functions` folder contains household, borrowing, and location functions. Install dependencies with pnpm 11 and run:

```sh
cd functions
pnpm install --frozen-lockfile
pnpm run build
pnpm test
```

From the repository root, `firebase emulators:start --project demo-app-5` runs local emulators (Firebase CLI and Java required). Deploying Cloud Functions later requires Blaze billing. Review and complete the scaffold before connecting the real app. See `docs/firebase-contracts.md` for the retained data/function contracts.
