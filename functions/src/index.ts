import { initializeApp } from 'firebase-admin/app';
import { photoBucket } from './photos';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { requireText, canBorrow, itemFields } from './validation';

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

export const createHousehold = onCall(async (request) => {
  const userId = uid(request.auth);
  const name = text(request.data?.name, 'name');
  const household = db.collection('households').doc();
  const batch = db.batch();
  batch.set(household, { name, ownerId: userId, createdAt: FieldValue.serverTimestamp() });
  batch.set(household.collection('members').doc(userId), { role: 'owner', joinedAt: FieldValue.serverTimestamp() });
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
    transaction.set(loan, { itemId, borrower, recordedBy: userId, dueDate: Timestamp.fromMillis(dueDate), borrowedAt: FieldValue.serverTimestamp(), returnedAt: null });
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
    transaction.update(household.collection('loans').doc(activeLoanId), { returnedAt: FieldValue.serverTimestamp() });
    transaction.update(item, { activeLoanId: null });
  });
  return { returned: true };
});

// All reads that protect a mutation occur in the same transaction as the write.
export const createLocation = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const name = text(request.data?.name, 'name');
  const kind = locationKind(request.data?.kind);
  const household = db.collection('households').doc(householdId);
  const parentId = kind === 'container' ? text(request.data?.parentId, 'parentId') : null;
  if (kind === 'room' && request.data?.parentId != null) throw new HttpsError('invalid-argument', 'Rooms cannot have a parent.');
  const location = household.collection('locations').doc();
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (parentId !== null) {
      const parent = await tx.get(household.collection('locations').doc(parentId));
      if (parent.data()?.kind !== 'room') throw new HttpsError('failed-precondition', 'Choose an existing room.');
    }
    tx.create(location, { name, kind, parentId, createdAt: FieldValue.serverTimestamp() });
  });
  return { locationId: location.id };
});

export const renameLocation = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const locationId = text(request.data?.locationId, 'locationId');
  const name = text(request.data?.name, 'name');
  const household = db.collection('households').doc(householdId);
  const location = household.collection('locations').doc(locationId);
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    const snapshot = await tx.get(location);
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Location not found.');
    tx.update(location, { name, updatedAt: FieldValue.serverTimestamp() });
  });
  return { renamed: true };
});

export const deleteLocation = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const locationId = text(request.data?.locationId, 'locationId');
  const household = db.collection('households').doc(householdId);
  const location = household.collection('locations').doc(locationId);
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    const snapshot = await tx.get(location);
    const items = await tx.get(household.collection('items').where('locationId', '==', locationId).limit(1));
    const children = await tx.get(household.collection('locations').where('parentId', '==', locationId).limit(1));
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Location not found.');
    if (!items.empty || !children.empty) throw new HttpsError('failed-precondition', 'Move items and containers before deleting this location.');
    tx.delete(location);
  });
  return { deleted: true };
});

export const moveItem = onCall(async (request) => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const itemId = text(request.data?.itemId, 'itemId');
  const locationId = request.data?.locationId == null ? null : text(request.data.locationId, 'locationId');
  const household = db.collection('households').doc(householdId);
  const item = household.collection('items').doc(itemId);
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    const snapshot = await tx.get(item);
    const destination = locationId === null ? null : await tx.get(household.collection('locations').doc(locationId));
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) throw new HttpsError('not-found', 'Item not found.');
    if (locationId !== null && !destination?.exists) throw new HttpsError('not-found', 'Location not found.');
    tx.update(item, { locationId, revision: (snapshot.data()?.revision ?? 0) + 1, updatedAt: FieldValue.serverTimestamp() });
  });
  return { moved: true };
});

async function saveItem(request: { auth?: { uid: string }; data: any }, creating: boolean) {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const itemId = text(request.data?.itemId, 'itemId');
  let fields;
  try { fields = itemFields(request.data, householdId, itemId); }
  catch (error) { throw new HttpsError('invalid-argument', (error as Error).message); }
  const household = db.collection('households').doc(householdId);
  const item = household.collection('items').doc(itemId);
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    const snapshot = await tx.get(item);
    const destination = fields.locationId === null ? null : await tx.get(household.collection('locations').doc(fields.locationId));
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (creating && snapshot.exists) throw new HttpsError('already-exists', 'This item was already saved. Close the form and check your inventory.');
    if (!creating && !snapshot.exists) throw new HttpsError('not-found', 'Item no longer exists.');
    if (!creating && request.data.revision !== (snapshot.data()?.revision ?? 0)) throw new HttpsError('aborted', 'This item changed on another phone. Reopen it before editing.');
    if (fields.locationId !== null && !destination?.exists) throw new HttpsError('not-found', 'Choose an existing location.');
    if (fields.photoPath !== null && fields.photoPath !== snapshot.data()?.photoPath) {
      let metadata;
      try { [metadata] = await photoBucket().file(fields.photoPath).getMetadata(); }
      catch { throw new HttpsError('failed-precondition', 'Upload the photo before saving the item.'); }
      if (metadata.timeCreated && Date.parse(metadata.timeCreated) < Date.now() - 23 * 3600000) throw new HttpsError('failed-precondition', 'Select the photo again before saving.');
      if (!metadata.contentType?.startsWith('image/') || Number(metadata.size) >= 5 * 1024 * 1024) throw new HttpsError('invalid-argument', 'Choose an image smaller than 5 MB.');
    }
    const values = { ...fields, revision: (snapshot.data()?.revision ?? 0) + 1, updatedAt: FieldValue.serverTimestamp() };
    if (creating) tx.create(item, { ...values, activeLoanId: null, createdAt: FieldValue.serverTimestamp() });
    else tx.update(item, values);
  });
  return { itemId };
}

export const createItem = onCall(request => saveItem(request, true));
export const updateItem = onCall(request => saveItem(request, false));
export const deleteItem = onCall(async request => {
  const userId = uid(request.auth);
  const householdId = text(request.data?.householdId, 'householdId');
  const itemId = text(request.data?.itemId, 'itemId');
  const household = db.collection('households').doc(householdId);
  const item = household.collection('items').doc(itemId);
  await db.runTransaction(async tx => {
    const membership = await tx.get(household.collection('members').doc(userId));
    const snapshot = await tx.get(item);
    if (!membership.exists) throw new HttpsError('permission-denied', 'Join this household first.');
    if (!snapshot.exists) return; // Retrying a successful deletion is harmless.
    if (!canBorrow(snapshot.data()?.activeLoanId)) throw new HttpsError('failed-precondition', 'Return this item before deleting it.');
    tx.delete(item);
  });
  return { deleted: true };
});

export { cleanupItemPhoto, cleanupAbandonedPhotos } from './photos';
