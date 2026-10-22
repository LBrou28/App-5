import { createHash, randomBytes } from 'node:crypto';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { requireText } from './validation';

const invitationHash = (code: string) => createHash('sha256').update(code).digest('hex');

export const createHouseholdInvite = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  let householdId: string;
  try { householdId = requireText(request.data?.householdId, 'householdId'); }
  catch { throw new HttpsError('invalid-argument', 'Choose a household.'); }
  const db = getFirestore();
  const code = randomBytes(18).toString('base64url');
  const invitation = db.collection('householdInvites').doc(invitationHash(code));
  await db.runTransaction(async tx => {
    const membership = await tx.get(db.doc(`households/${householdId}/members/${request.auth!.uid}`));
    if (membership.data()?.role !== 'owner') throw new HttpsError('permission-denied', 'Only the household owner can invite members.');
    tx.create(invitation, { householdId, createdBy: request.auth!.uid, expiresAt: Timestamp.fromMillis(Date.now() + 86400000), usedBy: null });
  });
  return { code };
});

export const joinHousehold = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const code = request.data?.code;
  if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{24}$/.test(code.trim())) throw new HttpsError('invalid-argument', 'Enter the full invitation code.');
  const db = getFirestore();
  const userId = request.auth.uid;
  const invitation = db.collection('householdInvites').doc(invitationHash(code.trim()));
  return db.runTransaction(async tx => {
    const invite = (await tx.get(invitation)).data();
    if (!invite || (invite.usedBy !== null && invite.usedBy !== userId) || invite.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError('failed-precondition', 'This invitation has expired or was already used. Ask for a new code.');
    }
    const householdId = invite.householdId as string;
    const household = await tx.get(db.doc(`households/${householdId}`));
    const inviter = await tx.get(db.doc(`households/${householdId}/members/${invite.createdBy}`));
    const member = db.doc(`households/${householdId}/members/${userId}`);
    const existing = await tx.get(member);
    if (!household.exists || inviter.data()?.role !== 'owner') throw new HttpsError('failed-precondition', 'This household invitation is no longer valid.');
    if (!existing.exists) tx.create(member, { role: 'member', joinedAt: FieldValue.serverTimestamp() });
    tx.update(invitation, { usedBy: userId });
    tx.set(db.doc(`users/${userId}`), { householdIds: FieldValue.arrayUnion(householdId), activeHouseholdId: householdId }, { merge: true });
    return { householdId };
  });
});
