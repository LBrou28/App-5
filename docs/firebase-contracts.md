# Firebase data and callable contracts

## Firestore layout

- `users/{uid}`: `householdIds` (managed by server).
- `users/{uid}/favorites/{householdId}_{itemId}`: `householdId`, `itemId`, `createdAt`. Private to the user; the item must exist when the favorite is written. The app removes the user's own favorite when they delete the item; other users' stale favorites are ignored because the app only shows favorites that match a loaded item.
- `households/{householdId}`: `name`, `ownerId`, `createdAt`.
- `households/{householdId}/members/{uid}`: `role`, `joinedAt`.
- `households/{householdId}/locations/{locationId}`: `name`, `kind` (`room` or `container`), `parentId` (null for rooms), `createdAt`, optional `updatedAt`. A container's parent is always a room.
- `households/{householdId}/items/{itemId}`: `name`, `category` (≤100 chars, may be empty), `locationId` (null when unassigned), `notes` (≤2000 chars, may be empty), `activeLoanId` (null when available), `createdAt`, `updatedAt`, optional `photoPath`. The app creates and deletes items in Firestore transactions that also adjust the location's `itemCount`; items on loan cannot be deleted.
- `households/{householdId}/loans/{loanId}`: `itemId`, `borrower`, `recordedBy`, `dueDate`, `borrowedAt`, `returnedAt`.

Photo object path: `households/{householdId}/items/{itemId}/{fileName}`. Prefer authenticated Storage SDK reads when photos must remain private; do not distribute permanent download-token URLs.

## Implemented functions

All require Firebase Authentication. Default region: us-central1.

- `createHousehold({name})` returns `{householdId}` and creates owner membership.
- `borrowItem({householdId, itemId, borrower, dueDate})` returns `{loanId}`. dueDate is epoch milliseconds, future and within 366 days. Checks membership and item existence and atomically prevents a second active loan.
- `returnItem({householdId, itemId})` returns `{returned: true}`. Checks membership, marks loan returned and clears active loan atomically; history remains.

## Next functions to implement

Student 1: create/update/delete items and coordinate photo lifecycle.
Student 2: on the Spark plan, room/container create, rename, delete, and item moves run in Firestore transactions from the app rather than deployed Cloud Functions. Each location stores `itemCount` and `childCount`; those counters are adjusted atomically and deletion rejects a nonzero count. The callable implementations remain in source for a future Blaze deployment but are not used by the app.
Student 3: household-scoped read queries, user favorites and scalable search if needed. For a small initial inventory, local search over loaded household items supports substring search in names and notes. Implemented in the app: a Discover screen (favorites, categories, recently added, unassigned items), multi-word search over item name, category, notes and location, category and favorites filters (`lib/features/locations/item_filter.dart`), and per-user favorites.
Student 4: server-validated household invitation/join/leave flows, account screens and reminders. Handle leaving the last owner and revoking access.

## Security and tests

Client Security Rules deny shared writes and allow reads only to members. Favorites are private to the user; writes validate household membership and item existence. Storage rules allow member image uploads under 5 MB. Add emulator integration tests covering outsider denial, malformed writes, concurrent loans, stale membership and returns before live deployment. Current server tests verify input guards only; they do not replace emulator tests.
