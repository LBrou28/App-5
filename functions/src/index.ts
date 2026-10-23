import { initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { requireText, canBorrow } from './validation';

initializeApp();
const db = getFirestore();

function uid(auth: { uid: string } | undefined): string {
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  return auth.uid;
}

function text(value: unknown, name: string): string {
  try { return requireText(value, name); }
  catch { throw new HttpsError('invalid-argument', `${name} is required and must be a valid identifier or name.`); }
}

function locationKind(value: unknown): 'room' | 'container' {
  if (value === 'room' || value === 'container') return value;
  throw new HttpsError('invalid-argument', 'kind must be room or container.');
}

async function requireMember(householdId: string, userId: string) {
  const household = db.collection('households').doc(householdId);
  if (!(await household.collection('members').doc(userId).get()).exists) {
    throw new HttpsError('permission-denied', 'Join this household first.');
  }
  return household;
}

export const createHousehold = onCall(async (request) => {
  const userId = uid(request.auth);
  const name = text(request.data?.name, 'name');
  const household = db.collection('households').doc();
  const batch = db.batch();
  batch.set(household, { name, ownerId: userId, createdAt: FieldValue.serverTimestamp() });
  batch.set(household.collection('members').doc(userId), { role: 'owner', displayName: request.auth?.token.name ?? request.auth?.token.email ?? 'Household owner', joinedAt: FieldValue.serverTimestamp() });
  batch.set(db.collection('users').doc(userId), { householdIds: FieldValue.arrayUnion(household.id) }, { merge: true });
  await batch.commit();
  return { householdId: household.id };
});

export const borrowItem = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const itemId = text(request.data?.itemId, 'itemId');
  const borrower = text(request.data?.borrower, 'borrower');
  const dueDate = request.data?.dueDate;
  if (typeof dueDate !== 'number' || !Number.isFinite(dueDate) || dueDate <= Date.now() || dueDate > Date.now() + 366 * 86400000) {
    throw new HttpsError('invalid-argument', 'dueDate must be a future epoch-millisecond timestamp within one year.');
  }
  const household = db.collection('households').doc(householdId);
  const item = household.collection('items').doc(itemId);
  const loan = household.collection('loans').doc();
  await db.runTransaction(async (transaction) => {
    const [membership, snapshot] = await Promise.all([
      transaction.get(household.collection('members').doc(userId)),
      transaction.get(item),
    ]);
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Item not found.');
    if (!canBorrow(snapshot.data()?.activeLoanId)) throw new HttpsError('failed-precondition', 'Item is already borrowed.');
    transaction.set(loan, { itemId, itemName: snapshot.data()?.name ?? 'Unnamed item', borrower, recordedBy: userId, dueDate: Timestamp.fromMillis(dueDate), borrowedAt: FieldValue.serverTimestamp(), returnedAt: null });
    transaction.update(item, { activeLoanId: loan.id });
  });
  return { loanId: loan.id };
});

export const returnItem = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const itemId = text(request.data?.itemId, 'itemId');
  const household = db.collection('households').doc(householdId);
  const item = household.collection('items').doc(itemId);
  await db.runTransaction(async (transaction) => {
    const [membership, snapshot] = await Promise.all([
      transaction.get(household.collection('members').doc(userId)),
      transaction.get(item),
    ]);
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Item not found.');
    const activeLoanId = snapshot.data()?.activeLoanId;
    if (typeof activeLoanId !== 'string' || !activeLoanId) throw new HttpsError('failed-precondition', 'Item has no active loan.');
    const loan = household.collection('loans').doc(activeLoanId);
    const history = await transaction.get(loan);
    if (!history.exists || history.data()?.itemId !== itemId || history.data()?.returnedAt != null) throw new HttpsError('failed-precondition', 'Loan record does not match this item.');
    transaction.update(loan, { returnedAt: FieldValue.serverTimestamp() });
    transaction.update(item, { activeLoanId: null });
  });
  return { returned: true };
});

export const createLocation = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const name = text(request.data?.name, 'name');
  const kind = locationKind(request.data?.kind);
  const household = await requireMember(householdId, userId);
  const parentId = request.data?.parentId;
  if (kind === 'container') {
    const parent = typeof parentId === 'string' ? await household.collection('locations').doc(parentId).get() : undefined;
    if (parent?.data()?.kind !== 'room') {
      throw new HttpsError('failed-precondition', 'A container must belong to an existing room.');
    }
  } else if (parentId != null) throw new HttpsError('invalid-argument', 'Rooms cannot have a parent.');
  const location = household.collection('locations').doc();
  await location.set({ name, kind, parentId: kind === 'container' ? parentId : null, createdAt: FieldValue.serverTimestamp() });
  return { locationId: location.id };
});

export const renameLocation = onCall(async (request) => {
  const userId = uid(request.auth); const householdId = text(request.data?.householdId, 'householdId');
  const locationId = text(request.data?.locationId, 'locationId'); const name = text(request.data?.name, 'name');
  const household = await requireMember(householdId, userId); const location = household.collection('locations').doc(locationId);
  if (!(await location.get()).exists) throw new HttpsError('not-found', 'Location not found.');
  await location.update({ name, updatedAt: FieldValue.serverTimestamp() }); return { renamed: true };
});

export const deleteLocation = onCall(async (request) => {
  const userId = uid(request.auth); const householdId = text(request.data?.householdId, 'householdId'); const locationId = text(request.data?.locationId, 'locationId');
  const household = await requireMember(householdId, userId); const location = household.collection('locations').doc(locationId);
  await db.runTransaction(async (transaction) => {
    const [locationSnapshot, items, children] = await Promise.all([
      transaction.get(location), transaction.get(household.collection('items').where('locationId', '==', locationId).limit(1)),
      transaction.get(household.collection('locations').where('parentId', '==', locationId).limit(1)),
    ]);
    if (!locationSnapshot.exists) throw new HttpsError('not-found', 'Location not found.');
    if (!items.empty || !children.empty) throw new HttpsError('failed-precondition', 'Move items and containers before deleting this location.');
    transaction.delete(location);
  }); return { deleted: true };
});

export const moveItem = onCall(async (request) => {
  const userId = uid(request.auth); const householdId = text(request.data?.householdId, 'householdId'); const itemId = text(request.data?.itemId, 'itemId');
  const locationId = request.data?.locationId; if (locationId != null && typeof locationId !== 'string') throw new HttpsError('invalid-argument', 'locationId must be a string or null.');
  const household = await requireMember(householdId, userId); const item = household.collection('items').doc(itemId);
  await db.runTransaction(async (transaction) => {
    const [itemSnapshot, locationSnapshot] = await Promise.all([transaction.get(item), locationId == null ? Promise.resolve(undefined) : transaction.get(household.collection('locations').doc(locationId))]);
    if (!itemSnapshot.exists) throw new HttpsError('not-found', 'Item not found.');
    if (locationId != null && !locationSnapshot?.exists) throw new HttpsError('not-found', 'Destination location not found.');
    transaction.update(item, { locationId: locationId ?? null, updatedAt: FieldValue.serverTimestamp() });
  }); return { moved: true };
});

export { createInvitation, joinHousehold, leaveHousehold } from './sharing';


