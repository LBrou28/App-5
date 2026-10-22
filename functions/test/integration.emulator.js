const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { getFirestore } = require('firebase-admin/firestore');
const { deleteApp, getApps } = require('firebase-admin/app');

// This suite refuses live projects and never runs as part of unit tests.
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) {
  throw new Error('Run with Firebase emulators and a demo-* project.');
}
const functions = require('../lib/index');
const db = getFirestore();
const call = (name, uid, data) => functions[name].run({ auth: uid ? { uid } : undefined, data });
let householdId, roomId, containerId;
const itemId = 'toolbox';
const base = () => ({ householdId, itemId, name: 'Toolbox', category: 'Tools', notes: 'Top shelf', locationId: containerId, photoPath: null });

before(async () => {
  ({ householdId } = await call('createHousehold', 'owner', { name: 'Test household' }));
  await db.doc(`households/${householdId}/members/second`).set({ role: 'member' });
  ({ locationId: roomId } = await call('createLocation', 'owner', { householdId, name: 'Garage', kind: 'room' }));
  ({ locationId: containerId } = await call('createLocation', 'owner', { householdId, name: 'Cabinet', kind: 'container', parentId: roomId }));
});
after(async () => { await Promise.all(getApps().map(deleteApp)); });

test('item lifecycle, household boundaries, stale edits, loans and safe location deletion', async () => {
  await assert.rejects(call('createItem', null, base()), { code: 'unauthenticated' });
  await assert.rejects(call('createItem', 'outsider', base()), { code: 'permission-denied' });
  await assert.rejects(call('createItem', 'owner', { ...base(), locationId: 'missing' }), { code: 'not-found' });
  await assert.rejects(call('createItem', 'owner', { ...base(), photoPath: 'households/other/items/toolbox/photo' }), { code: 'invalid-argument' });
  await call('createItem', 'owner', base());
  await assert.rejects(call('createItem', 'owner', base()), { code: 'already-exists' });
  let snapshot = await db.doc(`households/${householdId}/items/${itemId}`).get();
  assert.equal(snapshot.data().locationId, containerId);
  await assert.rejects(call('deleteLocation', 'owner', { householdId, locationId: containerId }), { code: 'failed-precondition' });
  await call('updateItem', 'second', { ...base(), revision: 1, name: 'Shared toolbox' });
  await assert.rejects(call('updateItem', 'owner', { ...base(), revision: 1 }), { code: 'aborted' });
  await call('moveItem', 'second', { householdId, itemId, locationId: roomId });
  snapshot = await db.doc(`households/${householdId}/items/${itemId}`).get();
  assert.equal(snapshot.data().name, 'Shared toolbox');
  assert.equal(snapshot.data().locationId, roomId);
  assert.equal(snapshot.data().revision, 3);
  await call('deleteLocation', 'owner', { householdId, locationId: containerId });
  const results = await Promise.allSettled(['owner', 'second'].map(uid => call('borrowItem', uid, { householdId, itemId, borrower: uid, dueDate: Date.now() + 86400000 })));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter(r => r.status === 'rejected')[0].reason.code, 'failed-precondition');
  await assert.rejects(call('deleteItem', 'owner', { householdId, itemId }), { code: 'failed-precondition' });
  await assert.rejects(call('returnItem', 'outsider', { householdId, itemId }), { code: 'permission-denied' });
  await call('returnItem', 'owner', { householdId, itemId });
  await call('deleteItem', 'second', { householdId, itemId });
  await call('deleteItem', 'second', { householdId, itemId });
  assert.equal((await db.doc(`households/${householdId}/items/${itemId}`).get()).exists, false);
  assert.equal((await db.collection(`households/${householdId}/loans`).get()).size, 1);
  await call('deleteLocation', 'owner', { householdId, locationId: roomId });
});

async function token(uid) {
  // Emulator accepts unsigned ID tokens with the Firebase project's claims.
  const part = x => Buffer.from(JSON.stringify(x)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${part({alg:'none',typ:'JWT'})}.${part({iss:`https://securetoken.google.com/${process.env.GCLOUD_PROJECT}`,aud:process.env.GCLOUD_PROJECT,sub:uid,user_id:uid,iat:now,exp:now+3600,auth_time:now,firebase:{sign_in_provider:'custom',identities:{}}})}.`;
}
async function clientDocument(uid, path, method = 'GET', body) {
  return fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents/${path}`, {
    method, headers: { Authorization: `Bearer ${await token(uid)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined,
  });
}

test('Firestore rules allow household reads and deny direct shared mutations', async () => {
  const path = `households/${householdId}/items/rules-item`;
  await db.doc(path).set({name:'Private item',activeLoanId:null});
  assert.equal((await clientDocument('second', path)).status, 200);
  assert.equal((await clientDocument('outsider', path)).status, 403);
  assert.equal((await clientDocument('second', path, 'PATCH', {fields:{activeLoanId:{nullValue:null}}})).status, 403);
  assert.equal((await clientDocument('second', path, 'DELETE')).status, 403);
  assert.equal((await clientDocument('owner', `households/${householdId}/loans/fake`, 'PATCH', {fields:{itemId:{stringValue:'rules-item'}}})).status, 403);
  assert.equal((await clientDocument('outsider', `households/${householdId}/members/outsider`, 'PATCH', {fields:{role:{stringValue:'owner'}}})).status, 403);
  assert.equal((await clientDocument('owner', 'users/owner', 'PATCH', {fields:{householdIds:{arrayValue:{values:[]}}}})).status, 403);
});

const { getStorage } = require('firebase-admin/storage');
const bucket = `${process.env.GCLOUD_PROJECT}.appspot.com`;
async function storageRequest(uid, path, method = 'GET', bytes, contentType = 'image/png') {
  const endpoint = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${bucket}/o`;
  return fetch(method === 'POST' ? `${endpoint}?uploadType=media&name=${encodeURIComponent(path)}` : `${endpoint}/${encodeURIComponent(path)}?alt=media`, {
    method, headers: { Authorization: `Firebase ${await token(uid)}`, 'Content-Type': contentType }, body: bytes,
  });
}

test('private photos upload, persist, reject outsiders and clean up after replacement/deletion', async () => {
  const itemId = 'photo-item';
  const photoPath = `households/${householdId}/items/${itemId}/first`;
  const secondPath = `households/${householdId}/items/${itemId}/second`;
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=', 'base64');
  assert.equal((await storageRequest('outsider', photoPath, 'POST', png)).status, 403);
  assert.equal((await storageRequest('owner', photoPath, 'POST', png)).status, 200);
  assert.equal((await storageRequest('owner', photoPath, 'POST', png)).status, 403);
  assert.equal((await storageRequest('second', photoPath)).status, 200);
  assert.equal((await storageRequest('outsider', photoPath)).status, 403);
  assert.equal((await storageRequest('owner', `households/${householdId}/items/${itemId}/bad`, 'POST', Buffer.from('text'), 'text/plain')).status, 403);
  assert.equal((await storageRequest('owner', `households/${householdId}/items/${itemId}/large`, 'POST', Buffer.alloc(5*1024*1024))).status, 403);
  const data = {householdId,itemId,name:'Photographed item',photoPath};
  await call('createItem', 'owner', data);
  assert.equal((await db.doc(`households/${householdId}/items/${itemId}`).get()).data().photoPath, photoPath);
  await assert.rejects(call('updateItem', 'owner', {...data,revision:1,photoPath:`households/${householdId}/items/${itemId}/missing`}), {code:'failed-precondition'});
  assert.equal((await storageRequest('owner', secondPath, 'POST', png)).status, 200);
  await call('updateItem', 'owner', {...data,revision:1,photoPath:secondPath});
  await functions.cleanupItemPhoto.run({params:{householdId,itemId},data:{before:{data:()=>({photoPath})},after:{data:()=>({photoPath:secondPath})}}});
  assert.equal((await getStorage().bucket(bucket).file(photoPath).exists())[0], false);
  await call('deleteItem', 'owner', {householdId,itemId});
  await functions.cleanupItemPhoto.run({params:{householdId,itemId},data:{before:{data:()=>({photoPath:secondPath})},after:{data:()=>undefined}}});
  assert.equal((await getStorage().bucket(bucket).file(secondPath).exists())[0], false);
});
