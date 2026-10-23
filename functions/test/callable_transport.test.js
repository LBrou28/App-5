const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, createUserWithEmailAndPassword } = require('firebase/auth');
const { getFirestore, connectFirestoreEmulator, doc, setDoc, getDoc, getDocs, collection, serverTimestamp, terminate, setLogLevel } = require('firebase/firestore');
const { getFunctions, connectFunctionsEmulator, httpsCallable } = require('firebase/functions');

// Explicit opt-in and local endpoints are required; this test never targets deployed services.
const enabled = process.env.RUN_CALLABLE_SMOKE === '1'
  && Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST)
  && Boolean(process.env.FIRESTORE_EMULATOR_HOST);

test('two authenticated clients share inventory and borrow through callable HTTP transport', { skip: !enabled, timeout: 90000 }, async () => {
  setLogLevel('silent');
  const projectId = process.env.GCLOUD_PROJECT || 'demo-app-5';
  const suffix = randomUUID();
  const clients = [];
  function client(label) {
    const app = initializeApp({ apiKey: 'local-emulator-key', projectId, appId: `local-${label}` }, `${label}-${suffix}`);
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
    const db = getFirestore(app);
    const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
    connectFirestoreEmulator(db, host, Number(port));
    const functions = getFunctions(app, 'us-central1');
    connectFunctionsEmulator(functions, '127.0.0.1', 5001);
    const result = { app, auth, db, call: (name, data) => httpsCallable(functions, name)(data).then(response => response.data) };
    clients.push(result);
    return result;
  }
  const a = client('a'), b = client('b');
  try {
    await assert.rejects(a.call('createHousehold', { name: 'Unauthenticated' }), error => error.code === 'functions/unauthenticated');
    await createUserWithEmailAndPassword(a.auth, `a-${suffix}@example.test`, 'local-test-password');
    await createUserWithEmailAndPassword(b.auth, `b-${suffix}@example.test`, 'local-test-password');
    const { householdId } = await a.call('createHousehold', { name: 'Transport test home' });
    const { code } = await a.call('createInvitation', { householdId });
    await b.call('joinHousehold', { code });
    const itemPath = `households/${householdId}/items/drill`;
    await setDoc(doc(a.db, itemPath), { name: 'Shared drill', category: 'Tools', notes: '', locationId: null, activeLoanId: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    assert.equal((await getDoc(doc(b.db, itemPath))).data().name, 'Shared drill');
    const { loanId } = await a.call('borrowItem', { householdId, itemId: 'drill', borrower: 'Neighbor', dueDate: Date.now() + 86400000 });
    assert.equal((await getDoc(doc(b.db, itemPath))).data().activeLoanId, loanId);
    await assert.rejects(b.call('borrowItem', { householdId, itemId: 'drill', borrower: 'Another person', dueDate: Date.now() + 86400000 }), error => error.code === 'functions/failed-precondition');
    await b.call('returnItem', { householdId, itemId: 'drill' });
    assert.equal((await getDoc(doc(a.db, itemPath))).data().activeLoanId, null);
    const history = await getDocs(collection(a.db, `households/${householdId}/loans`));
    assert.equal(history.size, 1);
    assert.equal(history.docs[0].data().itemName, 'Shared drill');
    assert.ok(history.docs[0].data().returnedAt);
    await b.call('leaveHousehold', { householdId });
    await assert.rejects(getDoc(doc(b.db, itemPath)), error => error.code === 'permission-denied');
  } finally {
    for (const client of clients) { await terminate(client.db); await deleteApp(client.app); }
  }
});
