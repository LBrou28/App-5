# App-5

Flutter household inventory with Google sign-in, rooms, containers, item locations, invitation-based sharing, borrowing records and local phone return reminders.

## Authentication and storage locations

The app initializes Firebase from `lib/firebase_options.dart`, shows a Google sign-in screen, lets new users create or join a household, and stores rooms, containers, and item locations in Firestore. Anonymous sessions are upgraded to Google credentials without losing their household data. Google sign-in is enabled in Firebase Authentication; Android builds still need their debug and release SHA-1 fingerprints registered in Firebase Project Settings before native sign-in will work.

## Run

Use Flutter 3.47.2 or newer (Dart 3.13.2):

```sh
flutter pub get
flutter run
```

Platform projects are included for Android, iOS, macOS, and web. Android requires Android SDK; iOS and macOS require a Mac with Xcode. 

## Checks

```sh
flutter analyze
flutter test
```

## Retained Firebase scaffold

Firebase is initialized using the checked-in `lib/firebase_options.dart`. Firestore/Storage rules, emulator configuration and Cloud Functions are included in source; confirm their deployment in the Firebase project before using live flows.

When targeting a different project, run `flutterfire configure` to regenerate `lib/firebase_options.dart`. Choose the matching project for Firebase CLI using `firebase use --add`.

The `functions` folder contains household, borrowing, and location functions. Install dependencies with pnpm 11 and run:

```sh
cd functions
pnpm install --frozen-lockfile
pnpm run build
pnpm test
```

From the repository root, `firebase emulators:start --project demo-app-5` runs local emulators (Firebase CLI and Java required). Deploying Cloud Functions later requires Blaze billing. Review and complete the scaffold before connecting the real app. See `docs/firebase-contracts.md` for the retained data/function contracts.

## Sharing and borrowing

Use the account menu to create/join/switch households, view members and invitations, and open Borrowed items. Google sign-in also registers new users. See [Student 4 setup and acceptance checks](docs/student-4.md) for callable deployment, emulator tests and phone reminders. These sharing/borrowing flows require deployed Cloud Functions (Blaze); they are not Spark-only.


