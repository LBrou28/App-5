# Student 4: sharing and borrowing

The account menu opens **Account & household** and **Borrowed items**. Google sign-in signs in existing users and registers new Firebase users. Users without a household choose Create or Join; existing users can switch between households.

## Server setup

This implementation uses the callable Functions required by the Trello card. Deploy Functions and Firestore rules together before testing against the live Firebase project. Cloud Functions deployment requires the Blaze plan; these flows cannot run solely on Spark. No Firebase resources were deployed by this change. Existing location/item transactions still run from the client.

From `functions`, install dependencies, build and test:

```sh
pnpm install --frozen-lockfile
pnpm run build
pnpm test
```

With the Firebase CLI and Java 21 installed, from the repository root run:

```sh
firebase emulators:exec --only firestore --project demo-app-5 "pnpm --dir functions test"
```

The integration test is skipped when `FIRESTORE_EMULATOR_HOST` is absent. It exercises the real callable handlers against emulator data and checks Firestore rules from authenticated client contexts. It never targets production data.

## Membership contracts

- `createHousehold({name}) -> {householdId}` creates the owner, household and server-owned user membership index.
- `createInvitation({householdId}) -> {code, expiresAt}` requires the owner. Codes have 128 bits of randomness and expire in seven days. The server stores only a SHA-256 hash in `householdInvitations/{hash}`; client rules expose none of this collection. Multiple people can reuse a code during its validity period.
- `joinHousehold({code}) -> {householdId}` validates the invitation, expiry, household and inviter's ownership inside a transaction. Rejoining is idempotent and never changes the owner's role.
- `leaveHousehold({householdId}) -> {left:true}` removes membership and the user index together. The designated owner cannot leave; ownership transfer and household deletion are outside this implementation. Access is denied immediately by membership rules after leaving.

Members include `role`, `displayName`, `joinedAt`. Existing records without a display name display a fallback. Memberships, user indexes, loans and item `activeLoanId` changes are server-only; arbitrary client writes cannot bypass concurrent-loan protection.

## Loans and reminders

`borrowItem` atomically verifies membership and item availability, records the current server loan date and a future expected return instant, then links the item to the loan. `returnItem` verifies the matching active loan and preserves its record while clearing the item's active loan ID. New loans retain the item name as well as its ID, so history stays readable after an item is renamed or deleted. Older loan records without a saved name use the current item name when available.

The recording phone requests notification permission after the loan succeeds and schedules an Android/iOS local notification for the selected return date/time. Failed or denied notification setup never retries the already-recorded loan. Android uses an inexact alarm, so delivery can be delayed by battery/OS policy; reboot rescheduling is configured. Dates are entered in the device's local timezone and scheduled as UTC instants.

The inventory's loan listener cancels reminders for returned loans in the currently open household. Sign-out clears all pending device reminders; leaving a household clears only that household's reminders. A phone that is offline or has the app closed cannot learn that another phone returned an item until it reconnects with that household open. Web and desktop support sharing/borrowing but do not schedule phone reminders.

## Two-phone acceptance check

1. Deploy the Functions/rules together. Register Android SHA fingerprints for Google sign-in or use configured iOS credentials.
2. On phone A sign in, create a household, add an item, and create an invitation from Account & household.
3. On phone B sign in with a different account and join using that code. Confirm the household's items and both members are visible.
4. Record a loan on A with a near-future return time. Allow notifications. Confirm B sees it in Borrowed items and the inventory says On loan.
5. Attempt a simultaneous second loan: only one may succeed. Check an overdue loan is labeled Overdue.
6. Return the item on B. A should move the loan to History and cancel the local reminder when connected. Confirm the item is available again.
7. Record another loan and verify a reminder on A while the app is backgrounded. Check notification-denied behavior separately.
8. Leave on B and confirm access disappears. Confirm A, the owner, cannot leave.

Automated checks do not replace these physical-phone sign-in, notification delivery and demo checks.

## Local rehearsal without deployment

Debug builds can connect all four Firebase services to your computer. This uses the configured project ID `app-5-741f2` for consistency between client and emulators; all app reads, writes and callable requests go to the local emulators in this mode. Fake accounts are available only after emulator configuration succeeds. Release/profile builds reject the emulator flag.

Install the Firebase CLI and Java 21 first. From the repository root:

```sh
pnpm --dir functions run build
firebase emulators:start --config firebase.local.json --only auth,firestore,functions,storage --project app-5-741f2
```

`firebase.local.json` binds emulator services to the computer's local network so phones on the same Wi-Fi can connect; use it for the local rehearsal. It does not change the deployment configuration in `firebase.json`.

In another terminal, run the web app:

```sh
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATORS=true
```

On the Android emulator, the app defaults to `10.0.2.2` for the computer. On an actual phone, set the computer's LAN IP explicitly:

```sh
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.20
```

Replace the example IP with your computer's address. The host flag takes a hostname/IP only, without scheme or port. The four ports are 9099 (Auth), 8080 (Firestore), 5001 (Functions) and 9199 (Storage). Android debug builds allow HTTP for these endpoints; release configuration is unchanged.

The sign-in screen offers **local test account A** and **local test account B**, which are created/reused in the Auth emulator without Google credentials. Open two separate browser profiles or devices, select different accounts, and follow the two-phone acceptance steps above. Use web for sharing/borrowing rehearsal and Android/iOS phones for notification delivery. Emulator mode cannot verify production Google sign-in, deployed Functions, or native phone permissions; those checks remain necessary.

For production, omit both dart defines and use the normal Google sign-in screen. Emulator data is ephemeral unless you explicitly export/import it with the Firebase CLI.

## Callable transport acceptance test

In PowerShell, run this from the repository root with Firebase CLI installed:

```powershell
$env:RUN_CALLABLE_SMOKE = '1'
firebase emulators:exec --only auth,firestore,functions --project demo-app-5 "pnpm --dir functions run test:transport"
Remove-Item Env:RUN_CALLABLE_SMOKE
```

The test creates two separate Auth clients and checks the actual callable HTTP path: unauthenticated denial, create/invite/join, shared inventory, borrowing, duplicate-loan rejection, return/history and loss of access after leaving. It uses generated test accounts and runs only when the Auth and Firestore emulator hosts are present. The default test command skips this transport test unless explicitly enabled.

Firebase references: [connect the Auth emulator](https://firebase.google.com/docs/emulator-suite/connect_auth), [Flutter Auth setup](https://firebase.google.com/docs/auth/flutter/start).

The two-client callable transport acceptance test has been run successfully with local Auth, Functions and Firestore emulators. Physical-phone notification delivery and production Google sign-in/deployment remain separate acceptance checks.
