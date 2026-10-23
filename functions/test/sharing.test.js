const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, setLogLevel } = require('firebase/firestore');

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
test('household membership, loan concurrency and access revocation', { skip: !enabled }, async () => {
  setLogLevel('silent');
  const projectId = 'demo-app-5';
  process.env.GCLOUD_PROJECT = projectId;
  const environment = await initializeTestEnvironment({ projectId, firestore: { rules: readFileSync('../firestore.rules', 'utf8') } });
  const functions = require('../lib/index');
  const { getFirestore } = require('firebase-admin/firestore');
  const db = getFirestore();
  const request = (uid, data) => ({ auth: { uid, token: { name: uid } }, data });
  try {
    await environment.clearFirestore();
    await assert.rejects(functions.createHousehold.run({ data: { name: 'Home' } }), /Sign in/);
    const { householdId } = await functions.createHousehold.run(request('owner', { name: 'Home' }));
    const home = db.collection('households').doc(householdId);
    const { code } = await functions.createInvitation.run(request('owner', { householdId }));
    await assert.rejects(functions.joinHousehold.run(request('outsider', { code: 'invalid' })), /invalid or expired/);
    await functions.joinHousehold.run(request('member', { code }));
    await functions.joinHousehold.run(request('member', { code }));
    assert.equal((await home.collection('members').get()).size, 2);
    await assert.rejects(functions.createInvitation.run(request('member', { householdId })), /Only the owner/);
    const { code: expiredCode } = await functions.createInvitation.run(request('owner', { householdId }));
    const { createHash } = require('node:crypto');
    const { Timestamp } = require('firebase-admin/firestore');
    await db.collection('householdInvitations').doc(createHash('sha256').update(expiredCode).digest('hex')).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1) });
    await assert.rejects(functions.joinHousehold.run(request('outsider', { code: expiredCode })), /invalid or expired/);
    const memberDb = environment.authenticatedContext('member').firestore();
    await assertFails(updateDoc(doc(memberDb, 'users/member'), { householdIds: ['forged'] }));
    await assertFails(updateDoc(doc(memberDb, 'households/' + householdId + '/members/member'), { role: 'owner' }));
    const outsiderDb = environment.authenticatedContext('outsider').firestore();
    const itemId = 'drill';
    await home.collection('items').doc(itemId).set({ name: 'Drill', activeLoanId: null });
    await getDoc(doc(memberDb, `households/${householdId}/items/${itemId}`));
    await assertFails(getDoc(doc(outsiderDb, `households/${householdId}/items/${itemId}`)));
    await assertFails(setDoc(doc(outsiderDb, `households/${householdId}/members/outsider`), { role: 'owner' }));
    await assertFails(updateDoc(doc(memberDb, `households/${householdId}/items/${itemId}`), { activeLoanId: 'forged' }));
    await assertFails(setDoc(doc(memberDb, `households/${householdId}/loans/forged`), { borrower: 'fake' }));
    await assert.rejects(functions.borrowItem.run(request('outsider', { householdId, itemId, borrower: 'Other', dueDate: Date.now()+86400000 })), /Join this household/);
    await assert.rejects(functions.borrowItem.run(request('member', { householdId, itemId, borrower: 'Other', dueDate: Date.now()-1 })), /future/);
    const races = await Promise.allSettled(['owner', 'member'].map(uid => functions.borrowItem.run(request(uid, { householdId, itemId, borrower: 'Friend', dueDate: Date.now()+86400000 }))));
    assert.equal(races.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal((await home.collection('loans').get()).size, 1);
    assert.equal((await home.collection('loans').get()).docs[0].data().itemName, 'Drill');
    await functions.returnItem.run(request('member', { householdId, itemId }));
    assert.equal((await home.collection('items').doc(itemId).get()).data().activeLoanId, null);
    assert.ok((await home.collection('loans').get()).docs[0].data().returnedAt);
    await home.collection('items').doc(itemId).update({ name: 'Renamed drill' });
    assert.equal((await home.collection('loans').get()).docs[0].data().itemName, 'Drill');
    await assert.rejects(functions.returnItem.run(request('member', { householdId, itemId })), /no active loan/);
    await assert.rejects(functions.leaveHousehold.run(request('owner', { householdId })), /owner cannot leave/);
    await functions.leaveHousehold.run(request('member', { householdId }));
    await assertFails(getDoc(doc(memberDb, `households/${householdId}/items/${itemId}`)));
    await assert.rejects(functions.borrowItem.run(request('member', { householdId, itemId, borrower: 'Friend', dueDate: Date.now()+86400000 })), /Join this household/);
    assert.deepEqual((await db.collection('users').doc('member').get()).data().householdIds, []);
  } finally { await environment.cleanup(); }
});



