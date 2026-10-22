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

`borrowItem` atomically verifies membership and item availability, records the current server loan date and a future expected return instant, then links the item to the loan. `returnItem` verifies the matching active loan and preserves its record while clearing the item's active loan ID. Loan history retains the item ID if an item is later deleted.

The recording phone requests notification permission after the loan succeeds and schedules an Android/iOS local notification for the selected return date/time. Failed or denied notification setup never retries the already-recorded loan. Android uses an inexact alarm, so delivery can be delayed by battery/OS policy; reboot rescheduling is configured. Dates are entered in the device's local timezone and scheduled as UTC instants.

The inventory's loan listener cancels reminders for returned loans in the currently open household. Sign-out/leave clears pending device reminders. A phone that is offline or has the app closed cannot learn that another phone returned an item until it reconnects with that household open. Web and desktop support sharing/borrowing but do not schedule phone reminders.

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
