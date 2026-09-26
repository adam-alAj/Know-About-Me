// Firestore Security Rules tests.
//
// Run with the Firebase Emulator Suite:
//   firebase emulators:exec --only firestore "node --test firebase/test/"
//
// These tests are the executable specification of docs/architecture/FIREBASE_SECURITY.md.
// They never touch a real Firebase project: everything runs against the local
// emulator, which is why the project id uses the documented `demo-` prefix.
//
// The scenarios covered are exactly the ones required by the Phase 3 brief:
//   - unauthenticated access is denied,
//   - user isolation (A cannot read B's private data),
//   - pair isolation (A cannot read an unrelated pair),
//   - an authorized active-pair member can read only what is explicitly shared,
//   - disabled/not-enabled categories are not readable,
//   - a disconnected/revoked member loses access,
//   - unauthorized writes and privileged transitions are rejected.

const fs = require('node:fs');
const path = require('node:path');
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  query,
  where,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-kam';
const RULES_PATH = path.join(__dirname, '..', 'firestore.rules');

let testEnv;

const ts = () => Timestamp.fromDate(new Date());

// ---------------------------------------------------------------- seeding ---

async function seedPair(db, pairId, { memberIds, status }) {
  await setDoc(doc(db, 'pairs', pairId), {
    memberIds,
    status,
    requestedBy: memberIds[0],
    createdAt: ts(),
    updatedAt: ts(),
  });
}

async function seedSharing(db, pairId, userId, categories, paused = false) {
  await setDoc(doc(db, 'pairs', pairId, 'sharing', userId), {
    userId,
    pairId,
    paused,
    categories,
    updatedAt: ts(),
  });
}

async function seedDeviceState(db, pairId, ownerId, fields) {
  await setDoc(doc(db, 'pairs', pairId, 'deviceState', ownerId), {
    ownerUserId: ownerId,
    observedAt: ts(),
    updatedAt: ts(),
    ...fields,
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Two unrelated users and their private documents.
    await setDoc(doc(db, 'users', 'uA'), {
      displayName: 'Afraa',
      photoUrl: null,
      timeZone: 'Europe/Berlin',
      createdAt: ts(),
      updatedAt: ts(),
    });
    await setDoc(doc(db, 'users', 'uB'), {
      displayName: 'Adam',
      createdAt: ts(),
      updatedAt: ts(),
    });
    await setDoc(doc(db, 'users', 'uC'), {
      displayName: 'Stranger',
      createdAt: ts(),
      updatedAt: ts(),
    });
    await setDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      homeLocation: { latitude: 52.5, longitude: 13.4, label: 'Home', radiusKm: 0.3 },
      notificationPreference: 'allRuleNotifications',
    });
    await setDoc(doc(db, 'users', 'uA', 'fcmTokens', 'tok1'), {
      platform: 'android',
      deviceId: 'devA',
      createdAt: ts(),
    });
    await setDoc(doc(db, 'users', 'uA', 'rules', 'r1'), {
      ownerUserId: 'uA',
      pairId: 'p1',
      name: 'Possible sleep',
      condition: { metric: 'chargingDuration', operator: 'greaterThan', numericThreshold: 240 },
      actions: [{ type: 'displayProbability', probabilityPercent: 70, isUserDefined: true }],
      enabled: true,
      cooldownSeconds: 1800,
      createdAt: ts(),
      updatedAt: ts(),
    });
    await setDoc(doc(db, 'users', 'uA', 'notifications', 'n1'), {
      pairId: 'p1',
      title: 'Possible sleep',
      body: 'There is a 70% possibility that Afraa is sleeping now.',
      category: 'ruleInterpretation',
      read: false,
      createdAt: ts(),
    });

    // p1: uA <-> uB, active. uA shares battery + network (NOT location).
    await seedPair(db, 'p1', { memberIds: ['uA', 'uB'], status: 'active' });
    await seedSharing(db, 'p1', 'uA', ['battery', 'network']);
    await seedSharing(db, 'p1', 'uB', ['battery']);
    await seedDeviceState(db, 'p1', 'uA', { batteryPercentage: 82, networkState: 'online' });
    await seedDeviceState(db, 'p1', 'uB', { batteryPercentage: 41 });
    await setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), {
      ownerUserId: 'uA',
      latitude: 52.51,
      longitude: 13.41,
      observedAt: ts(),
      updatedAt: ts(),
    });

    // p2: two unrelated users.
    await seedPair(db, 'p2', { memberIds: ['uC', 'uD'], status: 'active' });
    await seedSharing(db, 'p2', 'uC', ['battery']);
    await seedDeviceState(db, 'p2', 'uC', { batteryPercentage: 10 });

    // p3: uA <-> uE, still pending (not authorized yet).
    await seedPair(db, 'p3', { memberIds: ['uA', 'uE'], status: 'pending' });
    await seedSharing(db, 'p3', 'uA', ['battery']);
    await seedDeviceState(db, 'p3', 'uA', { batteryPercentage: 82 });
  });
});

const as = (userId) => testEnv.authenticatedContext(userId).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

// ------------------------------------------------------- unauthenticated ----

test('unauthenticated clients cannot read application data', async () => {
  const db = anon();
  await assertFails(getDoc(doc(db, 'users', 'uA')));
  await assertFails(getDoc(doc(db, 'pairs', 'p1')));
  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
});

test('unauthenticated clients cannot create a pair', async () => {
  const db = anon();
  await assertFails(
    setDoc(doc(db, 'pairs', 'pNew'), {
      memberIds: ['uA', 'uB'],
      status: 'pending',
      requestedBy: 'uA',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

// -------------------------------------------------------- user isolation ----

test('a user cannot read another user\'s profile or settings', async () => {
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'users', 'uA')));
  await assertFails(getDoc(doc(db, 'users', 'uA', 'settings', 'preferences')));
});

test('partner scoped data does not expose home coordinates', async () => {
  // Even inside an active pair, the partner reads a derived distance from the
  // shared state document, never the owner's home location document.
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'users', 'uA', 'settings', 'preferences')));
});

test('a user cannot read another user\'s rules, tokens or notifications', async () => {
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
  await assertFails(getDoc(doc(db, 'users', 'uA', 'fcmTokens', 'tok1')));
  await assertFails(getDoc(doc(db, 'users', 'uA', 'notifications', 'n1')));
});

test('a user can read their own private data', async () => {
  const db = as('uA');
  await assertSucceeds(getDoc(doc(db, 'users', 'uA')));
  await assertSucceeds(getDoc(doc(db, 'users', 'uA', 'settings', 'preferences')));
  await assertSucceeds(getDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
  await assertSucceeds(getDoc(doc(db, 'users', 'uA', 'fcmTokens', 'tok1')));
  await assertSucceeds(getDoc(doc(db, 'users', 'uA', 'notifications', 'n1')));
});

// -------------------------------------------------------- pair isolation ----

test('a user cannot read an unrelated pair or its subcollections', async () => {
  const db = as('uA');
  await assertFails(getDoc(doc(db, 'pairs', 'p2')));
  await assertFails(getDoc(doc(db, 'pairs', 'p2', 'deviceState', 'uC')));
  await assertFails(getDoc(doc(db, 'pairs', 'p2', 'sharing', 'uC')));
});

test('a user can list only the pairs they belong to', async () => {
  const db = as('uA');
  const mine = query(
    collection(db, 'pairs'),
    where('memberIds', 'array-contains', 'uA'),
  );
  const snapshot = await assertSucceeds(getDocs(mine));

  assert.deepEqual(
    snapshot.docs.map((d) => d.id).sort(),
    ['p1', 'p3'],
  );
});

// -------------------------------------------------- authorized pair read ----

test('an active pair member can read the categories the owner shares', async () => {
  const db = as('uB');
  const snapshot = await assertSucceeds(
    getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')),
  );

  assert.equal(snapshot.data().batteryPercentage, 82);
  assert.equal(snapshot.data().networkState, 'online');
});

test('the owner can always read their own state', async () => {
  const db = as('uA');
  await assertSucceeds(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
  await assertSucceeds(getDoc(doc(db, 'pairs', 'p1', 'location', 'uA')));
});

test('location is not readable when the location category is not shared', async () => {
  // uA shares battery + network only, so the partner must not see location.
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'location', 'uA')));
});

test('location becomes readable once the location category is shared', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network', 'location']);
  });

  const db = as('uB');
  await assertSucceeds(getDoc(doc(db, 'pairs', 'p1', 'location', 'uA')));
});

test('a non-member cannot read shared state', async () => {
  const db = as('uC');
  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
});

// --------------------------------------------- paused / pending / revoked ---

test('pausing sharing hides the partner\'s data immediately', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network'], true);
  });

  const db = as('uB');
  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
  // The owner can still see their own data while paused.
  await assertSucceeds(
    getDoc(doc(as('uA'), 'pairs', 'p1', 'deviceState', 'uA')),
  );
});

test('a pending (not yet authorized) pair grants no access to shared data', async () => {
  const db = as('uE');
  await assertFails(getDoc(doc(db, 'pairs', 'p3', 'deviceState', 'uA')));
});

test('a member who disconnects loses access to the partner\'s data', async () => {
  const db = as('uB');
  await assertSucceeds(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));

  // uB leaves: disconnected is a client-permitted transition.
  await assertSucceeds(
    updateDoc(doc(db, 'pairs', 'p1'), {
      status: 'disconnected',
      updatedAt: serverTimestamp(),
    }),
  );

  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
});

test('a revoked pair grants no access', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'pairs', 'p1'), { status: 'revoked' });
  });

  const db = as('uB');
  await assertFails(getDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA')));
});

// ------------------------------------------------- unauthorized writes -----

test('a user cannot write another user\'s device state', async () => {
  const db = as('uB');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), {
      batteryPercentage: 1,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('the owner cannot store a category they have not shared', async () => {
  // uB shares only battery, so writing networkState must be rejected.
  const db = as('uB');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uB'), {
      networkState: 'online',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('the owner cannot write their location while location sharing is off', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), {
      latitude: 1.0,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a client cannot activate a pair by itself', async () => {
  const db = as('uE');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p3'), {
      status: 'active',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('pair membership cannot be changed by a member', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1'), {
      memberIds: ['uA', 'uC'],
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a member cannot raise the owner\'s sharing permissions', async () => {
  const db = as('uB');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'sharing', 'uA'), {
      categories: ['battery', 'network', 'location'],
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a sharing document cannot contain an unknown category', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'sharing', 'uA'), {
      categories: ['battery', 'everything'],
      updatedAt: serverTimestamp(),
    }),
  );
});

test('history events are append-only', async () => {
  const db = as('uA');
  const event = doc(db, 'pairs', 'p1', 'events', 'e1');

  await assertSucceeds(
    setDoc(event, {
      deviceId: 'devA',
      ownerUserId: 'uA',
      type: 'chargingStarted',
      category: 'charging',
      occurredAt: ts(),
      recordedAt: serverTimestamp(),
    }),
  );

  await assertFails(updateDoc(event, { type: 'chargingStopped' }));
  await assertFails(deleteDoc(event));
});

test('a member cannot record an event as another user', async () => {
  const db = as('uB');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'events', 'spoofed'), {
      deviceId: 'devA',
      ownerUserId: 'uA',
      type: 'deviceWentOffline',
      category: 'network',
      occurredAt: ts(),
      recordedAt: serverTimestamp(),
    }),
  );
});

test('notifications cannot be created or deleted by a client', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'notifications', 'fake'), {
      pairId: 'p1',
      title: 'Fake',
      body: 'Fake',
      category: 'ruleInterpretation',
      read: false,
      createdAt: ts(),
    }),
  );
  await assertFails(deleteDoc(doc(db, 'users', 'uA', 'notifications', 'n1')));
});

test('a user can only mark their own notification as read', async () => {
  await assertSucceeds(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), { read: true }),
  );
  await assertFails(
    updateDoc(doc(as('uB'), 'users', 'uA', 'notifications', 'n1'), { read: true }),
  );
  // Other fields are not writable even by the owner.
  await assertFails(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), { title: 'edited' }),
  );
});

// ------------------------------------------- interpretations (facts rule) ---

test('an interpretation must be flagged as user-defined', async () => {
  // uA shares interpretations for partner p1 (the default seed shares only
  // battery + network).
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', [
      'battery',
      'network',
      'ruleInterpretations',
    ]);
  });

  const db = as('uA');
  const base = {
    ownerUserId: 'uA',
    ruleId: 'r1',
    message: 'There is a 70% possibility that Adam is sleeping now.',
    probabilityPercent: 70,
    basis: [],
    producedAt: ts(),
  };

  // Claiming a measured probability is rejected.
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i1'), {
      ...base,
      isUserDefined: false,
    }),
  );

  // A user-configured interpretation is accepted.
  await assertSucceeds(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i2'), {
      ...base,
      isUserDefined: true,
    }),
  );
});

test('an interpretation cannot be created without sharing interpretations', async () => {
  // uB does not share ruleInterpretations.
  const db = as('uB');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i3'), {
      ownerUserId: 'uB',
      ruleId: 'rB',
      message: 'test',
      isUserDefined: true,
      basis: [],
      producedAt: ts(),
    }),
  );
});

test('interpretations are immutable once created', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i2'), {
      message: 'edited',
    }),
  );
});
