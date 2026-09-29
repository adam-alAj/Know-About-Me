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
  runTransaction,
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
    invitationCode: 'seeded-invitation',
    schemaVersion: 1,
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

// A member's own consent document. Shared under Spark terms: consent is what
// authorizes sharing now, and it can only ever be written by its own subject.
async function seedConsent(db, pairId, userId, granted) {
  await setDoc(doc(db, 'pairs', pairId, 'consents', userId), {
    userId,
    pairId,
    granted,
    categories: ['battery', 'network'],
    grantedAt: granted ? ts() : null,
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

    // p1: uA <-> uB, active, with BOTH consents granted. Consent is the
    // standing authority for sharing, so an active pair alone is no longer
    // enough to read partner data.
    await seedPair(db, 'p1', { memberIds: ['uA', 'uB'], status: 'active' });
    await seedConsent(db, 'p1', 'uA', true);
    await seedConsent(db, 'p1', 'uB', true);
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
    await seedConsent(db, 'p2', 'uC', true);
    await seedConsent(db, 'p2', 'uD', true);
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

test('an authenticated user cannot forge a pair without atomically redeeming an invitation', async () => {
  await assertFails(setDoc(doc(as('uE'), 'pairs', 'forged'), {
    memberIds: ['uA', 'uE'], status: 'pending', requestedBy: 'uE',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    invitationCode: CODE, schemaVersion: 1,
  }));
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

// ------------------------------------------------------- profile writes ----
// The Phase 4 authentication/profile work depends on these rules, so they are
// specified here rather than assumed: ownership, immutability of createdAt, and
// server-authoritative timestamps.

test('a user can create their own profile with server timestamps', async () => {
  const db = as('uNew');
  await assertSucceeds(
    setDoc(doc(db, 'users', 'uNew'), {
      displayName: 'Newcomer',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a user cannot create a profile for another user id', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'users', 'uOther'), {
      displayName: 'Impersonator',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a profile cannot be created without a display name', async () => {
  const db = as('uNew');
  await assertFails(
    setDoc(doc(db, 'users', 'uNew'), {
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uNew'), {
      displayName: '',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a profile cannot be backdated by the client', async () => {
  const db = as('uNew');
  await assertFails(
    setDoc(doc(db, 'users', 'uNew'), {
      displayName: 'Newcomer',
      createdAt: ts(),
      updatedAt: ts(),
    }),
  );
});

test('a user can update the editable fields of their own profile', async () => {
  const db = as('uA');
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'uA'), {
      displayName: 'Afraa B',
      timeZone: 'Europe/Paris',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a profile update cannot change createdAt', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA'), {
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a profile update must carry a server timestamp', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA'), { displayName: 'Afraa B', updatedAt: ts() }),
  );
});

test('a user cannot add arbitrary fields to their own profile', async () => {
  const db = as('uA');
  // hasOnly() on the post-update document is what stops a client from storing
  // authorisation-ish data on its own profile.
  await assertFails(
    updateDoc(doc(db, 'users', 'uA'), {
      admin: true,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a user cannot write or delete another user\'s profile', async () => {
  const db = as('uB');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA'), {
      displayName: 'Hijacked',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(doc(db, 'users', 'uA')));
});

test('unauthenticated clients cannot read or write a profile', async () => {
  const db = anon();
  await assertFails(getDoc(doc(db, 'users', 'uA')));
  await assertFails(
    setDoc(doc(db, 'users', 'uNew'), {
      displayName: 'Anonymous',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'uA'), {
      displayName: 'Anonymous',
      updatedAt: serverTimestamp(),
    }),
  );
});

// ----------------------------------------------------------------- settings --

test('the owner can store valid preferences', async () => {
  const db = as('uA');
  await assertSucceeds(
    setDoc(
      doc(db, 'users', 'uA', 'settings', 'preferences'),
      {
        notificationPreference: 'importantOnly',
        homeLocation: { latitude: 52.5, longitude: 13.4, radiusKm: 0.3 },
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    ),
  );
});

test('preferences reject unknown keys and unknown document ids', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      admin: true,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'settings', 'other'), {
      updatedAt: serverTimestamp(),
    }),
  );
});

test('preferences must carry a server timestamp', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      updatedAt: ts(),
    }),
  );
});

test('notificationPreference must be a known value', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      notificationPreference: 'everything',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('home location must be a valid coordinate', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      homeLocation: { latitude: 120, longitude: 13.4 },
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      homeLocation: { latitude: 52.5, longitude: 200 },
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      homeLocation: { latitude: -33.86, longitude: 151.2 },
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a user cannot write another user\'s preferences', async () => {
  const db = as('uB');
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'settings', 'preferences'), {
      notificationPreference: 'noNotifications',
      updatedAt: serverTimestamp(),
    }),
  );
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
      endedAt: serverTimestamp(),
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

// -------------------------------------- pair activation (Spark, no server) ---
// ADR-002 reserved activation for a Cloud Function. Under the Spark-only
// architecture (ADR-009) the rules perform the same check a trusted transaction
// would: both members' consent documents must already be granted. Neither user
// can write the other's consent, so the invariant cannot be forged.

test('a client cannot activate a pair by itself', async () => {
  const db = as('uE');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p3'), {
      status: 'active',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('an active pair cannot be created by one-sided consent', async () => {
  // Only uA agrees; uE has not.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedConsent(context.firestore(), 'p3', 'uA', true);
  });

  await assertFails(
    updateDoc(doc(as('uA'), 'pairs', 'p3'), {
      status: 'active',
      activatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a denied consent blocks activation even if the caller agrees', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await seedConsent(db, 'p3', 'uA', true);
    await seedConsent(db, 'p3', 'uE', false);
  });

  await assertFails(
    updateDoc(doc(as('uA'), 'pairs', 'p3'), {
      status: 'active',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a pair becomes active once BOTH members have granted consent', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await seedConsent(db, 'p3', 'uA', true);
    await seedConsent(db, 'p3', 'uE', true);
  });

  await assertSucceeds(
    updateDoc(doc(as('uA'), 'pairs', 'p3'), {
      status: 'active',
      activatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  // Access then follows the sharing categories, exactly as for a seeded pair.
  await assertSucceeds(
    getDoc(doc(as('uE'), 'pairs', 'p3', 'deviceState', 'uA')),
  );
});

test('activation cannot be attempted without a server timestamp', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await seedConsent(db, 'p3', 'uA', true);
    await seedConsent(db, 'p3', 'uE', true);
  });

  await assertFails(
    updateDoc(doc(as('uA'), 'pairs', 'p3'), { status: 'active', activatedAt: ts(), updatedAt: ts() }),
  );
});

test('revoking consent stops partner reads immediately', async () => {
  await assertSucceeds(getDoc(doc(as('uB'), 'pairs', 'p1', 'deviceState', 'uA')));

  // uA withdraws consent but leaves the pair 'active' and the category shared.
  // Reads must stop anyway: consent is the standing authority (NFR-002).
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedConsent(context.firestore(), 'p1', 'uA', false);
  });

  await assertFails(getDoc(doc(as('uB'), 'pairs', 'p1', 'deviceState', 'uA')));
});

// ------------------------------------------- pairing codes (Spark, no server) ---

const CODE = 'ABCDEFGH23456789XYZ1';
const inThirtyMinutes = () => Timestamp.fromMillis(Date.now() + 30 * 60 * 1000);

async function publishCode(db, userId, code, overrides = {}) {
  return setDoc(doc(db, 'pairingCodes', code), {
    code,
    createdByUserId: userId,
    revoked: false,
    status: 'created',
    usedByUserId: null,
    createdAt: serverTimestamp(),
    expiresAt: inThirtyMinutes(),
    ...overrides,
  });
}

test('a signed-in user can publish a well-formed pairing code', async () => {
  await assertSucceeds(publishCode(as('uA'), 'uA', CODE));
});

test('a pairing code must be long enough to be unguessable', async () => {
  await assertFails(publishCode(as('uA'), 'uA', 'TOOSHORT12345678901'));
});

test('a pairing code must expire within an hour', async () => {
  await assertFails(
    publishCode(as('uA'), 'uA', CODE, {
      expiresAt: Timestamp.fromMillis(Date.now() + 2 * 60 * 60 * 1000),
    }),
  );
  await assertFails(
    publishCode(as('uA'), 'uA', CODE, {
      expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    }),
  );
});

test('a user cannot publish a code on behalf of another user', async () => {
  await assertFails(publishCode(as('uB'), 'uA', CODE));
});

test('an unauthenticated client cannot read or publish pairing codes', async () => {
  await assertFails(getDoc(doc(anon(), 'pairingCodes', CODE)));
  await assertFails(publishCode(anon(), 'uA', CODE));
});

test('pairing codes cannot be listed, so outstanding codes cannot be harvested', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });
  await assertFails(getDocs(collection(as('uB'), 'pairingCodes')));
});

test('redemption and pending pair creation are one authorized transaction', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });
  const db = as('uE');
  await assertSucceeds(runTransaction(db, async (tx) => {
    const codeRef = doc(db, 'pairingCodes', CODE);
    const pairRef = doc(db, 'pairs', 'pending-uA-uE');
    await tx.get(codeRef);
    tx.update(codeRef, { usedByUserId: 'uE', usedAt: serverTimestamp(), status: 'consumed' });
    tx.set(pairRef, {
      memberIds: ['uA', 'uE'], status: 'pending', requestedBy: 'uE',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      invitationCode: CODE, schemaVersion: 1,
    });
  }));
});

test('a pairing code can be redeemed exactly once', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });

  await assertSucceeds(
    updateDoc(doc(as('uE'), 'pairingCodes', CODE), {
      usedByUserId: 'uE',
      usedAt: serverTimestamp(),
      status: 'consumed',
    }),
  );

  // A second user cannot consume the same code.
  await assertFails(
    updateDoc(doc(as('uF'), 'pairingCodes', CODE), {
      usedByUserId: 'uF',
      usedAt: serverTimestamp(),
      status: 'consumed',
    }),
  );
});

test('redeeming a code cannot smuggle other changes', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });

  await assertFails(
    updateDoc(doc(as('uE'), 'pairingCodes', CODE), {
      usedByUserId: 'uE',
      usedAt: serverTimestamp(),
      status: 'consumed',
      expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
    }),
  );
});

test('an expired pairing code cannot be redeemed', async () => {
  const expired = 'EXPIREDCODE123456789';
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // Seeded past its expiry: rules never allow creating one like this, which is
    // exactly why the redemption path re-checks the timestamp.
    await setDoc(doc(context.firestore(), 'pairingCodes', expired), {
      code: expired,
      createdByUserId: 'uA',
      revoked: false,
      status: 'created',
      usedByUserId: null,
      createdAt: ts(),
      expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    });
  });

  await assertFails(getDoc(doc(as('uE'), 'pairingCodes', expired)));
  await assertFails(
    updateDoc(doc(as('uE'), 'pairingCodes', expired), {
      usedByUserId: 'uE',
      usedAt: serverTimestamp(),
      status: 'consumed',
    }),
  );
});

test('only the issuer can cancel their pairing code', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });

  await assertFails(updateDoc(doc(as('uB'), 'pairingCodes', CODE), {
    revoked: true, status: 'cancelled', revokedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(as('uA'), 'pairingCodes', CODE), {
    revoked: true, status: 'cancelled', revokedAt: serverTimestamp(),
  }));
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

test('history events are immutable and only their owner may delete them', async () => {
  const db = as('uA');
  const event = doc(db, 'pairs', 'p1', 'events', 'e1');

  await assertSucceeds(
    setDoc(event, {
      ownerUserId: 'uA',
      type: 'deviceWentOffline',
      category: 'network',
      occurredAt: ts(),
      recordedAt: serverTimestamp(),
      source: 'device',
      schemaVersion: 1,
      deduplicationKey: 'stable-event-key',
      summary: 'Connectivity unavailable',
    }),
  );

  await assertFails(updateDoc(event, { type: 'chargingStopped' }));
  await assertSucceeds(deleteDoc(event));
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

test('history rejects fields outside the minimized event schema', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'events', 'private-data'), {
      ownerUserId: 'uA',
      type: 'deviceWentOffline',
      category: 'network',
      occurredAt: ts(),
      recordedAt: serverTimestamp(),
      source: 'device',
      schemaVersion: 1,
      exactCoordinates: { latitude: 52.5, longitude: 13.4 },
    }),
  );
});

test('history writes require the matching enabled sharing category', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'events', 'unshared-charge'), {
      ownerUserId: 'uA',
      type: 'chargingStarted',
      category: 'charging',
      occurredAt: ts(),
      recordedAt: serverTimestamp(),
      source: 'device',
      schemaVersion: 1,
    }),
  );
});

// Under Spark there is no server to write notifications, so the owner's own
// device does. That is only safe because the collection is strictly per-user.

test('the owner can record a local notification for themselves', async () => {
  await assertSucceeds(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'local1'), {
      recipientUserId: 'uA',
      pairId: 'p1',
      title: 'Possible sleep',
      body: 'There is a 70% possibility that Adam is sleeping now.',
      category: 'ruleInterpretation',
      read: false,
      delivered: false,
      createdAt: serverTimestamp(),
    }),
  );
});

test('a user cannot write a notification into someone else\'s collection', async () => {
  await assertFails(
    setDoc(doc(as('uB'), 'users', 'uA', 'notifications', 'injected'), {
      recipientUserId: 'uA',
      pairId: 'p1',
      title: 'Injected',
      body: 'Injected',
      category: 'ruleInterpretation',
      read: false,
      delivered: false,
      createdAt: serverTimestamp(),
    }),
  );
});

test('a notification cannot claim another user as its recipient', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'mislabelled'), {
      recipientUserId: 'uB',
      pairId: 'p1',
      title: 'Mislabeled',
      body: 'Mislabeled',
      category: 'ruleInterpretation',
      read: false,
      delivered: false,
      createdAt: serverTimestamp(),
    }),
  );
});

test('a notification cannot be created as already read or delivered', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'preset'), {
      recipientUserId: 'uA',
      pairId: 'p1',
      title: 'Preset',
      body: 'Preset',
      category: 'ruleInterpretation',
      read: true,
      delivered: true,
      createdAt: serverTimestamp(),
    }),
  );
});

test('a notification cannot be backdated by the client', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'backdated'), {
      recipientUserId: 'uA',
      pairId: 'p1',
      title: 'Backdated',
      body: 'Backdated',
      category: 'ruleInterpretation',
      read: false,
      delivered: false,
      createdAt: ts(),
    }),
  );
});

test('a notification cannot use an unknown category', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'badcat'), {
      recipientUserId: 'uA',
      pairId: 'p1',
      title: 'Bad category',
      body: 'Bad category',
      category: 'marketing',
      read: false,
      delivered: false,
      createdAt: serverTimestamp(),
    }),
  );
});

test('the owner can clear their own notification history', async () => {
  await assertSucceeds(deleteDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1')));
  await assertFails(deleteDoc(doc(as('uB'), 'users', 'uA', 'notifications', 'n1')));
});

test('a user can only mark their own notification as read', async () => {
  await assertSucceeds(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), { read: true }),
  );
  await assertFails(
    updateDoc(doc(as('uB'), 'users', 'uA', 'notifications', 'n1'), { read: true }),
  );
});

test('the owner can record delivery but cannot rewrite the message', async () => {
  await assertSucceeds(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), {
      read: true,
      delivered: true,
    }),
  );
  // A record cannot be rewritten into a different message after the fact.
  await assertFails(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), { title: 'edited' }),
  );
  await assertFails(
    updateDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'n1'), {
      body: 'edited body',
    }),
  );
});

test('a user cannot tamper with a consent document, even their own subject', async () => {
  // Consent subjects are fixed by the document id; a member can never write the
  // other member's consent, which is what makes activation unforgeable.
  await assertFails(
    updateDoc(doc(as('uB'), 'pairs', 'p1', 'consents', 'uA'), { granted: false }),
  );
  await assertFails(
    setDoc(doc(as('uB'), 'pairs', 'p1', 'consents', 'uA'), {
      userId: 'uA',
      pairId: 'p1',
      granted: false,
      categories: [],
    }),
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

// ============================ Phase 11: real-time synchronization ============
// These assertions are the executable specification of
// docs/security/FIRESTORE_DEVICE_STATE_SECURITY.md. They cover the properties
// the synchronization layer relies on: ownership binding, pair isolation,
// category gating on the *new* field set, value validation, state-version
// ordering, revocation, and location retraction.

/// A complete, well-formed device-state document as the Flutter writer sends it.
function sharedState(ownerId, fields = {}) {
  return {
    ownerUserId: ownerId,
    deviceId: 'opaque-device-id',
    schemaVersion: 1,
    stateVersion: 1,
    observedAt: ts(),
    updatedAt: serverTimestamp(),
    availabilityState: 'available',
    ...fields,
  };
}

/// A complete, well-formed location document. The path itself cannot carry
/// `latitude`/`longitude` (they are reserved words in these rules), so raw
/// listener reads are used below where the fields must be inspected.
function sharedLocation(ownerId, fields = {}) {
  return {
    ownerUserId: ownerId,
    deviceId: 'opaque-device-id',
    schemaVersion: 1,
    stateVersion: 1,
    observedAt: ts(),
    updatedAt: serverTimestamp(),
    ...fields,
  };
}

test('the owner can publish their own state with the documented field set', async () => {
  const db = as('uA');
  await assertSucceeds(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      networkState: 'online',
    })),
  );
});

test('a state write must be stamped by the server, not the client', async () => {
  const db = as('uA');
  // A client-chosen timestamp cannot prove when the server accepted the write.
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), {
      ownerUserId: 'uA',
      batteryPercentage: 71,
      updatedAt: ts(),
    }),
  );
});

test('a state write may not carry fields outside the documented set', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      rawGpsTrail: [1, 2, 3],
    })),
  );
});

test('a state write may not store a category the owner is not sharing', async () => {
  // uA shares battery + network only, so an activity field must be rejected.
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      screenState: 'on',
    })),
  );
});

test('state values are range- and type-checked before storage', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 101,
    })),
  );
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      isCharging: 'yes',
    })),
  );
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      networkState: 'maybe',
    })),
  );
});

test('a state observation may not be timestamped in the future', async () => {
  const db = as('uA');
  const future = Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000));
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      observedAt: future,
    })),
  );
});

test('an older snapshot cannot overwrite a newer one', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'pairs', 'p1', 'deviceState', 'uA'),
      { ownerUserId: 'uA', stateVersion: 7, updatedAt: ts() },
    );
  });

  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
      stateVersion: 6,
    })),
  );
});

test('a state write cannot claim another user as its owner', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uB', {
      batteryPercentage: 71,
    })),
  );
});

test('a member cannot publish state into an unrelated pair', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p2', 'deviceState', 'uC'), sharedState('uC', {
      batteryPercentage: 10,
    })),
  );
  // Nor into their own slot of someone else's pair.
  await assertFails(
    setDoc(doc(db, 'pairs', 'p2', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 10,
    })),
  );
});

test('a revoked pair can no longer receive state writes', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'pairs', 'p1'), {
      status: 'revoked',
    });
  });

  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 71,
    })),
  );
});

test('a disconnected pair stops accepting writes from both members', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'pairs', 'p1'), {
      status: 'disconnected',
    });
  });

  await assertFails(
    setDoc(doc(as('uB'), 'pairs', 'p1', 'deviceState', 'uB'), sharedState('uB', {
      batteryPercentage: 41,
    })),
  );
});

test('a member cannot widen their own sharing through a state write', async () => {
  // Authorization lives in the sharing document, which is keyed to its own
  // subject; a state write can never become an authorization change.
  const db = as('uB');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'sharing', 'uA'), {
      userId: 'uA',
      pairId: 'p1',
      paused: false,
      categories: ['battery', 'network', 'location'],
    }),
  );
});

// ------------------------------------------------ location write semantics ---

test('the owner can publish location once the category is shared', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network', 'location']);
  });

  const db = as('uA');
  await assertSucceeds(
    setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), sharedLocation('uA', {
      latitude: 52.51,
      longitude: 13.41,
      accuracyMeters: 18,
      approximate: false,
    })),
  );
});

test('location coordinates are range-checked', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network', 'location']);
  });

  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), sharedLocation('uA', {
      latitude: 91,
      longitude: 13.41,
    })),
  );
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), sharedLocation('uA', {
      latitude: 52.51,
      longitude: 13.41,
      accuracyMeters: -5,
    })),
  );
});

test('distance from home needs its own category, separately from coordinates', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network', 'location']);
  });

  const db = as('uA');
  // The `location` category alone does not authorize the derived distance.
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), sharedLocation('uA', {
      latitude: 52.51,
      longitude: 13.41,
      distanceFromHomeKm: 0.74,
      homePresence: 'awayFromHome',
    })),
  );
});

test('an unknown home presence value is rejected', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', [
      'battery',
      'network',
      'location',
      'distanceFromHome',
    ]);
  });

  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'location', 'uA'), sharedLocation('uA', {
      latitude: 52.51,
      longitude: 13.41,
      distanceFromHomeKm: 0.74,
      homePresence: 'definitelyHome',
    })),
  );
});

// ============================ Phase 14: rule definitions =====================
// Rule *definitions* are private to their owner (Phase 14). These assertions are
// the executable specification of the `users/{uid}/rules` rules block: owner
// binding, server-authoritative timestamps, a closed field set, type-checked
// values, and partner/cross-user isolation.

/// A complete, well-formed rule document as the Flutter writer sends it.
function validRule(ownerId, overrides = {}) {
  return {
    ownerUserId: ownerId,
    pairId: 'p1',
    name: 'Long Charging',
    version: 1,
    enabled: true,
    allowStaleData: false,
    cooldownSeconds: 1800,
    condition: {
      metric: 'chargingDuration',
      operator: 'greaterThanOrEqual',
      durationSeconds: 14400,
    },
    actions: [
      {
        type: 'displayProbability',
        messageTemplate: 'may be sleeping',
        probabilityPercent: 70,
        isUserDefined: true,
      },
    ],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    schemaVersion: 1,
    ...overrides,
  };
}

test('the owner can create a well-formed rule', async () => {
  const db = as('uA');
  await assertSucceeds(setDoc(doc(db, 'users', 'uA', 'rules', 'newRule'), validRule('uA')));
});

test('a rule can be created for the owner only', async () => {
  const db = as('uB');
  await assertFails(setDoc(doc(db, 'users', 'uA', 'rules', 'forged'), validRule('uA')));
  await assertFails(setDoc(doc(db, 'users', 'uA', 'rules', 'spoofed'), validRule('uB')));
});

test('an unauthenticated client cannot read or write rules', async () => {
  const db = anon();
  await assertFails(getDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
  await assertFails(setDoc(doc(db, 'users', 'uA', 'rules', 'anon'), validRule('uA')));
});

test('a rule write must be stamped by the server', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'backdated'), validRule('uA', {
      createdAt: ts(),
      updatedAt: ts(),
    })),
  );
});

test('a rule document may not carry fields outside the documented set', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'extra'), validRule('uA', { admin: true })),
  );
});

test('rule values are type- and range-checked before storage', async () => {
  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'badVersion'), validRule('uA', { version: 'one' })),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'badEnabled'), validRule('uA', { enabled: 'yes' })),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'badCooldown'), validRule('uA', { cooldownSeconds: -1 })),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'badCondition'), validRule('uA', { condition: 'nope' })),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'uA', 'rules', 'badSchema'), validRule('uA', { schemaVersion: 2 })),
  );
  await assertSucceeds(setDoc(doc(db, 'users', 'uA', 'rules', 'good'), validRule('uA')));
});

test('a rule can be edited with a server timestamp and keeps its creation time', async () => {
  const db = as('uA');
  await assertSucceeds(setDoc(doc(db, 'users', 'uA', 'rules', 'editable'), validRule('uA')));

  await assertSucceeds(
    updateDoc(doc(db, 'users', 'uA', 'rules', 'editable'), {
      name: 'Long Charging (5 hours)',
      version: 2,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a rule edit cannot backdate and cannot rewrite the creation time', async () => {
  const db = as('uA');
  await assertSucceeds(setDoc(doc(db, 'users', 'uA', 'rules', 'editable'), validRule('uA')));

  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'rules', 'editable'), {
      name: 'Backdated',
      updatedAt: ts(),
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'rules', 'editable'), {
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a user cannot read, edit or delete another user\'s rule', async () => {
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
  await assertFails(
    updateDoc(doc(db, 'users', 'uA', 'rules', 'r1'), {
      name: 'Hijacked',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
});

test('the owner may delete their own rule', async () => {
  const db = as('uB');
  await assertSucceeds(setDoc(doc(db, 'users', 'uB', 'rules', 'mine'), validRule('uB')));
  await assertSucceeds(deleteDoc(doc(db, 'users', 'uB', 'rules', 'mine')));
});

test('a partner cannot read the owner\'s rule definitions inside an active pair', async () => {
  // uA and uB share battery and network in p1, but rule definitions stay private.
  const db = as('uB');
  await assertFails(getDoc(doc(db, 'users', 'uA', 'rules', 'r1')));
  // A partner cannot even list another user's rule definitions.
  await assertFails(getDocs(collection(db, 'users', 'uA', 'rules')));
  // The owner can list their own.
  await assertSucceeds(getDocs(collection(as('uA'), 'users', 'uA', 'rules')));
});

// ==================== Phase 19: authorization hardening ======================
// Executable specification of docs/security/SECURITY_AND_AUTHORIZATION.md.
// Each test targets a specific threat (B, C, D, E, F, G, I, J, L, M, N).

// ------------------------------------------- privilege fields on profiles --
// Authorization is derived from Firestore relationships, never from a field a
// client set on its own document (constraint: client claim != trusted fact).

test('a profile cannot carry authorization-ish fields', async () => {
  const db = as('uA');
  for (const extra of [{ status: 'active' }, { activatedAt: ts() }, { isAdmin: true }, { isPartner: true }]) {
    await assertFails(
      updateDoc(doc(db, 'users', 'uA'), { ...extra, updatedAt: serverTimestamp() }),
    );
  }
});

// ------------------------------------------------------- sharing documents --
// Threat F: a client must not be able to widen or backdate the authorization
// document that the read rules consult.

test('the owner can update their own sharing with a server timestamp', async () => {
  await assertSucceeds(
    updateDoc(doc(as('uA'), 'pairs', 'p1', 'sharing', 'uA'), {
      paused: false,
      categories: ['battery'],
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a sharing change cannot be backdated or padded with unknown fields', async () => {
  const db = as('uA');
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'sharing', 'uA'), {
      categories: ['battery'],
      updatedAt: ts(),
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'pairs', 'p1', 'sharing', 'uA'), {
      categories: ['battery'],
      isAuthorized: true,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('a paused owner cannot keep publishing state', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', ['battery', 'network'], true);
  });

  await assertFails(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'deviceState', 'uA'), sharedState('uA', {
      batteryPercentage: 50,
    })),
  );
});

// ------------------------------------------------------------ device records --
// Threat E: a device id is a record key, never an authorization credential. A
// member may register only their own device, and the document is a closed shape.

test('a device record is bound to its owner and its path', async () => {
  await assertFails(
    setDoc(doc(as('uB'), 'pairs', 'p1', 'devices', 'devA'), {
      ownerUserId: 'uA', deviceId: 'devA', platform: 'android', lastSeenAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'devices', 'devA'), {
      ownerUserId: 'uA', deviceId: 'devB', platform: 'android', lastSeenAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'devices', 'devA'), {
      ownerUserId: 'uA', deviceId: 'devA', platform: 'android', lastSeenAt: serverTimestamp(),
    }),
  );
});

test('a device record cannot store hardware identifiers or extra fields', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'pairs', 'p1', 'devices', 'devX'), {
      ownerUserId: 'uA', deviceId: 'devX', platform: 'android',
      lastSeenAt: serverTimestamp(), serialNumber: 'IMEI-123', macAddress: 'aa:bb',
    }),
  );
});

test('a device record cannot be claimed by another member', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'pairs', 'p1', 'devices', 'devA'), {
      ownerUserId: 'uA', deviceId: 'devA', platform: 'android', lastSeenAt: ts(),
    });
  });

  // Ownership and platform are immutable, so a claim on someone else's device
  // is rejected and only a refresh of the presence timestamp is accepted.
  await assertFails(
    updateDoc(doc(as('uA'), 'pairs', 'p1', 'devices', 'devA'), {
      ownerUserId: 'uB', lastSeenAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(as('uB'), 'pairs', 'p1', 'devices', 'devA'), {
      lastSeenAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(as('uA'), 'pairs', 'p1', 'devices', 'devA'), {
      lastSeenAt: serverTimestamp(),
    }),
  );
});

// -------------------------------------------------------- interpretations --
// Threat L/M: an interpretation a partner can read is a closed, bounded shape.

test('an interpretation cannot store fields outside the documented set', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedSharing(context.firestore(), 'p1', 'uA', [
      'battery', 'network', 'ruleInterpretations',
    ]);
  });

  const db = as('uA');
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i-extra'), {
      ownerUserId: 'uA', ruleId: 'r1', message: 'ok', isUserDefined: true,
      basis: [], producedAt: ts(), payload: { secret: true },
    }),
  );
  await assertFails(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i-unbounded'), {
      ownerUserId: 'uA', ruleId: 'r1', message: 'x'.repeat(501), isUserDefined: true,
      basis: [], producedAt: ts(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(db, 'pairs', 'p1', 'interpretations', 'i-ok'), {
      ownerUserId: 'uA', ruleId: 'r1', message: 'ok', isUserDefined: true,
      basis: [], producedAt: ts(),
    }),
  );
});

// ---------------------------------------------------------- notifications --

test('a notification cannot carry fields outside the documented set', async () => {
  await assertFails(
    setDoc(doc(as('uA'), 'users', 'uA', 'notifications', 'extra'), {
      recipientUserId: 'uA', pairId: 'p1', title: 'T', body: 'B',
      category: 'system', read: false, delivered: false,
      createdAt: serverTimestamp(), admin: true,
    }),
  );
});

// ------------------------------------------------- two-person pair invariant --
// Threat I: a third account must never become a member of an existing pair.

test('a pair cannot be created with more than two members', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await publishCode(context.firestore(), 'uA', CODE);
  });

  const db = as('uE');
  await assertFails(runTransaction(db, async (tx) => {
    const codeRef = doc(db, 'pairingCodes', CODE);
    await tx.get(codeRef);
    tx.update(codeRef, { usedByUserId: 'uE', usedAt: serverTimestamp(), status: 'consumed' });
    tx.set(doc(db, 'pairs', 'three-members'), {
      memberIds: ['uA', 'uE', 'uC'], status: 'pending', requestedBy: 'uE',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      invitationCode: CODE, schemaVersion: 1,
    });
  }));
});

test('a member cannot add a third participant to an existing pair', async () => {
  await assertFails(
    updateDoc(doc(as('uA'), 'pairs', 'p1'), {
      memberIds: ['uA', 'uB', 'uC'], updatedAt: serverTimestamp(),
    }),
  );
});

// ------------------------------------------------------------------ history --
// Threat B/G/M: history is pair-scoped, append-only, and stops when the pair
// stops. An ended pair cuts partner history access on the next request.

test('unrelated users and ended pairs cannot read pair history', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'pairs', 'p1', 'events', 'e-history'), {
      ownerUserId: 'uA', type: 'deviceWentOffline', category: 'network',
      occurredAt: ts(), recordedAt: ts(), source: 'device', schemaVersion: 1,
    });
  });

  await assertFails(getDoc(doc(as('uC'), 'pairs', 'p1', 'events', 'e-history')));
  await assertSucceeds(getDoc(doc(as('uB'), 'pairs', 'p1', 'events', 'e-history')));

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'pairs', 'p1'), { status: 'revoked' });
  });

  // The partner loses access; the owner keeps their own records.
  await assertFails(getDoc(doc(as('uB'), 'pairs', 'p1', 'events', 'e-history')));
  await assertSucceeds(getDoc(doc(as('uA'), 'pairs', 'p1', 'events', 'e-history')));
});

test('a forged pair id cannot be used to read someone else\'s history', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'pairs', 'p2', 'events', 'e-p2'), {
      ownerUserId: 'uC', type: 'deviceWentOffline', category: 'network',
      occurredAt: ts(), recordedAt: ts(), source: 'device', schemaVersion: 1,
    });
  });

  await assertFails(getDoc(doc(as('uA'), 'pairs', 'p2', 'events', 'e-p2')));
  await assertFails(getDocs(collection(as('uA'), 'pairs', 'p2', 'events')));
});
