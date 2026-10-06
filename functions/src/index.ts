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
