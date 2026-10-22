# Firebase data and callable contracts

## Firestore layout

- `users/{uid}`: server-managed `householdIds`, `activeHouseholdId`.
- `users/{uid}/favorites/{id}`: `householdId`, `itemId`; private to the user and validated against household membership and an existing item.
- `households/{householdId}`: `name`, `ownerId`, `createdAt`.
- `households/{householdId}/members/{uid}`: `role`, `joinedAt`.
- `households/{householdId}/locations/{locationId}`: `name`, `kind` (`room` or `container`), `parentId` (null for rooms), `createdAt`, optional `updatedAt`. Containers belong to rooms. Legacy `itemCount`/`childCount` fields are ignored.
- `households/{householdId}/items/{itemId}`: `name`, `category` (at most 100 characters), `notes` (at most 2000), `locationId` (null when unassigned), `photoPath` (null without a photo), `activeLoanId` (null when available), `revision`, `createdAt`, `updatedAt`. Legacy items without `revision` are treated as revision 0.
- `households/{householdId}/loans/{loanId}`: `itemId`, `borrower`, `recordedBy`, `dueDate`, `borrowedAt`, `returnedAt`.
- `householdInvites/{sha256(code)}`: server-only `householdId`, `createdBy`, `expiresAt`, `usedBy`. Raw invitation codes are returned only to the creator.

Photo paths are `households/{householdId}/items/{itemId}/{randomId}`. The client uploads an immutable object before saving its reference. Photos are read through authenticated Storage SDK byte reads, not distributed download-token URLs. New references must target an existing image smaller than 5 MB uploaded within the last 23 hours. Unchanged existing references remain valid.

## Callable functions

All functions require Firebase Authentication and validate membership. Default region: `us-central1`.

| Function | Input | Result |
| --- | --- | --- |
| `createHousehold` | `{name}` | `{householdId}`; bootstrap is idempotent for an existing member |
| `createHouseholdInvite` | `{householdId}` | `{code}`; owner only, single use, expires in 24 hours |
| `joinHousehold` | `{code}` | `{householdId}`; joins and selects the household; same-user retries are safe |
| `createItem` | `{householdId,itemId,name,category?,notes?,locationId?,photoPath?}` | `{itemId}`; client reserves one stable ID per form to avoid duplicate creates after a lost response |
| `updateItem` | Same item fields plus `revision` | `{itemId}`; rejects stale edits; preserves loan status and creation time |
| `deleteItem` | `{householdId,itemId}` | `{deleted:true}`; rejects active loans; retry-safe |
| `createLocation` | `{householdId,name,kind,parentId?}` | `{locationId}` |
| `renameLocation` | `{householdId,locationId,name}` | `{renamed:true}` |
| `deleteLocation` | `{householdId,locationId}` | `{deleted:true}`; rejects locations containing items or containers |
| `moveItem` | `{householdId,itemId,locationId}` | `{moved:true}`; location may be null; increments revision |
| `borrowItem` | `{householdId,itemId,borrower,dueDate}` | `{loanId}`; future epoch milliseconds within 366 days; transaction prevents a second active loan |
| `returnItem` | `{householdId,itemId}` | `{returned:true}`; retains loan history |

Shared inventory reads use household-scoped Firestore listeners. Shared writes use Cloud Functions, not direct client writes or client-maintained counters. Membership and protected records are read within mutation transactions. The Storage bucket defaults to `app-5-741f2.firebasestorage.app`; set `ITEM_PHOTO_BUCKET` for other projects.

## Photo cleanup

`cleanupItemPhoto` removes the previous referenced photo after replacement or item deletion. It checks the current item before deleting, supports retries, and ignores already missing objects. `cleanupAbandonedPhotos` runs daily and removes unreferenced objects older than 24 hours. The client retains uploads after ambiguous errors because the item save may already have committed.

## Security and tests

Firestore rules allow shared reads only to members and deny direct shared mutations. User household context and membership are server-managed. Storage rules allow authenticated member reads and new image uploads below 5 MB; overwrites and client deletes are denied.

`pnpm test` validates input guards and photo-path boundaries. `pnpm run test:integration` starts Firestore/Storage emulators using `demo-app-5`, calls the actual function handlers, and verifies item CRUD, stale edits, two-member operations, outsider denial, safe location deletion, concurrent loans, private photos and single-use invitations. Trigger cleanup handlers run explicitly in these tests; a deployed Eventarc delivery still needs live verification.

## Other feature work

Search/favorites screens, borrowing/return screens, loan history display, reminders, household member management/leave flows, and the final demo video remain outside Student 1's item interface. These should use the shared contracts above rather than reintroducing direct shared writes.
