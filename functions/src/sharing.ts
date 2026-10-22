import { randomBytes, createHash } from 'node:crypto';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

const hash = (code: string) => createHash('sha256').update(code).digest('hex');
function id(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(value)) throw new HttpsError('invalid-argument', 'Invalid household or invitation code.');
  return value;
}
function user(auth: { uid: string } | undefined): string {
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  return auth.uid;
}

export const createInvitation = onCall(async request => {
  const uid = user(request.auth);
  const db = getFirestore();
  const householdId = id(request.data?.householdId);
  const household = db.collection('households').doc(householdId);
  const code = randomBytes(16).toString('hex');
  const expiresAt = Timestamp.fromMillis(Date.now() + 7 * 86400000);
  await db.runTransaction(async tx => {
    const member = await tx.get(household.collection('members').doc(uid));
    if (member.data()?.role !== 'owner') throw new HttpsError('permission-denied', 'Only the owner can invite members.');
    tx.set(db.collection('householdInvitations').doc(hash(code)), { householdId, expiresAt, createdBy: uid });
  });
  return { code, expiresAt: expiresAt.toMillis() };
});

export const joinHousehold = onCall(async request => {
  const uid = user(request.auth);
  const db = getFirestore();
  const code = id(request.data?.code).toLowerCase();
  const invitation = db.collection('householdInvitations').doc(hash(code));
  const householdId = await db.runTransaction(async tx => {
    const invite = (await tx.get(invitation)).data();
    if (!invite || !(invite.expiresAt instanceof Timestamp) || invite.expiresAt.toMillis() <= Date.now()) throw new HttpsError('not-found', 'Invitation is invalid or expired.');
    const household = db.collection('households').doc(invite.householdId);
    const member = household.collection('members').doc(uid);
    const [home, existing, inviter] = await Promise.all([tx.get(household), tx.get(member), tx.get(household.collection('members').doc(invite.createdBy))]);
    if (!home.exists || inviter.data()?.role !== 'owner') throw new HttpsError('not-found', 'Invitation is no longer valid.');
    if (!existing.exists) tx.set(member, { role: 'member', joinedAt: FieldValue.serverTimestamp(), displayName: request.auth?.token.name ?? request.auth?.token.email ?? 'Household member' });
    tx.set(db.collection('users').doc(uid), { householdIds: FieldValue.arrayUnion(household.id) }, { merge: true });
    return household.id;
  });
  return { householdId };
});

export const leaveHousehold = onCall(async request => {
  const uid = user(request.auth);
  const db = getFirestore();
  const householdId = id(request.data?.householdId);
  const home = db.collection('households').doc(householdId);
  await db.runTransaction(async tx => {
    const member = home.collection('members').doc(uid);
    const [membership, household] = await Promise.all([tx.get(member), tx.get(home)]);
    if (!membership.exists) throw new HttpsError('permission-denied', 'You are not a member.');
    if (membership.data()?.role === 'owner' || household.data()?.ownerId === uid) throw new HttpsError('failed-precondition', 'The household owner cannot leave. Other members can leave at any time.');
    tx.delete(member);
    tx.set(db.collection('users').doc(uid), { householdIds: FieldValue.arrayRemove(householdId) }, { merge: true });
  });
  return { left: true };
});
