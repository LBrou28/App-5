# App-5 — Where Did I Put It?

A Flutter household inventory app with Google sign-in, shared rooms and containers, and persistent item records. Student 1's flow supports adding, viewing, editing and deleting items; categories and notes; location assignment; and camera/gallery photos stored privately in Firebase Storage.

## Run

Use Flutter **3.47.7**, an Android SDK and Java 21. Firebase configuration for `app-5-741f2` is checked in; it identifies the app and is not a service-account credential.

```sh
flutter pub get --enforce-lockfile
flutter run
```

The app requires the Cloud Functions, Firestore rules and Storage rules in this repository to be deployed together. The earlier Spark-only direct-write implementation is no longer used. Cloud Functions and Cloud Storage require the Firebase project's Blaze billing setup. See [deployment and demo setup](docs/setup-and-demo.md).

## Automated build

Every push and pull request runs `.github/workflows/android.yml`:

- Flutter analysis and widget tests.
- An installable **debug Android APK**, available as the `app-5-debug-apk` Actions artifact for 14 days.
- Cloud Functions compilation and unit tests.
- Firestore and Storage emulator integration tests for household access, item changes, concurrent loans, photos and invitations.

This workflow builds and tests; it does not deploy Firebase. A debug APK is for development/demo use. Configure a stable debug signing key and register its SHA-1 in Firebase before using Google sign-in in CI-built APKs; instructions are in the setup guide.

## Local checks

```sh
flutter analyze
flutter test
flutter build apk --debug
cd functions
pnpm install --frozen-lockfile
pnpm run build
pnpm test
pnpm run test:integration
```

Use Node 22, pnpm 11 and Java 21 for server checks. Emulator tests use `demo-app-5` and refuse live projects. On Windows, ensure `JAVA_HOME` and `PATH` select Java 21.

## Shared household demo

Sign in on phone A and choose **Invite a member** from the account menu. On phone B, sign in with another Google account and choose **Join a household**. Enter the single-use code within 24 hours. The joined household remains selected after restart.

Add an item with a photo on A, open it on B, edit its notes/category/location, then delete it with confirmation. Both phones observe the same live Firestore inventory. Borrowed items cannot be deleted until returned. Loan functions are present; a borrowing UI, search/favorites screens, and reminders remain other feature work.

See [Firebase contracts](docs/firebase-contracts.md) for the shared schema and callable API. Platform projects are included for Android, iOS, macOS and web; this build workflow validates Android. iOS/macOS builds require a Mac and their platform sign-in setup.

## Local demo preview

Run `flutter run -d chrome --dart-define=DEMO_MODE=true` to explore the real inventory screens with sample data and no Firebase connection. Demo changes and photos stay in memory and reset on refresh. Normal builds still require sign-in.
