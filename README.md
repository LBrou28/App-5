# App-5

Standard Flutter starter application with Firebase scaffolding retained for future development. The app currently displays Flutter's default counter screen. No inventory screens or feature implementations are connected to the app.

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

The `functions` folder contains starter `createHousehold`, `borrowItem`, and `returnItem` functions. Install dependencies with pnpm 11 and run:

```sh
cd functions
pnpm install --frozen-lockfile
pnpm run build
pnpm test
```

From the repository root, `firebase emulators:start --project demo-app-5` runs local emulators (Firebase CLI and Java required). Deploying Cloud Functions later requires Blaze billing. Review and complete the scaffold before connecting the real app. See `docs/firebase-contracts.md` for the retained data/function contracts.
