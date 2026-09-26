# Firebase configuration and rules tests

Everything in this directory runs against the **Firebase Emulator Suite**. No real
Firebase project, account or credential is required.

Authoritative documentation:

- `../docs/architecture/FIREBASE_ARCHITECTURE.md` — services, environments, boundaries
- `../docs/architecture/FIRESTORE_DATA_MODEL.md` — collections and ownership
- `../docs/architecture/FIREBASE_SECURITY.md` — authorization model
- `../docs/decisions/ADR-007-firebase-integration.md` — why it is wired this way

---

## Files

| File | Purpose |
| --- | --- |
| `../firebase.json` | Firestore rules/indexes paths + emulator ports |
| `../.firebaserc` | Project aliases (`default` is the local `demo-kam`) |
| `firestore.rules` | Security rules (default-deny, pair-scoped) |
| `firestore.indexes.json` | Composite indexes for the queries the product needs |
| `package.json` | Node project for the rules tests |
| `test/firestore.rules.test.js` | 31 emulator tests covering the required scenarios |

---

## One-time setup

```bash
cd kam
npm --prefix firebase install        # installs @firebase/rules-unit-testing + firebase
firebase --version                   # requires the Firebase CLI
java -version                        # the Firestore emulator needs Java 11+
```

No `firebase login` is needed: `demo-kam` is a `demo-` prefixed project id, which
Firebase reserves for local emulator use.

---

## Run the rules tests

```bash
cd kam
firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"
```

Or, equivalently:

```bash
cd kam
firebase emulators:exec --only firestore "npm --prefix firebase test"
```

`emulators:exec` starts the emulator, runs the command with the real rules loaded,
then shuts everything down. A non-zero exit code means at least one rule allowed
or denied something it should not.

---

## Develop against the emulators

```bash
cd kam
firebase emulators:start --only firestore,auth
```

Then run the Flutter app pointed at the emulators:

```bash
flutter run \
  --dart-define=FIREBASE_PROJECT_ID=demo-kam \
  --dart-define=FIREBASE_API_KEY=demo-api-key \
  --dart-define=FIREBASE_APP_ID=1:000000000000:android:0000000000000000000000 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=000000000000 \
  --dart-define=FIREBASE_USE_EMULATORS=true
```

Emulator UI: <http://localhost:4000>

### Reset emulator data

- Stop the process: emulator data is in-memory and is discarded.
- Or wipe from a running session: `curl -X DELETE http://localhost:8080/emulator/v1/projects/demo-kam/databases/(default)/documents`
- The tests already call `clearFirestore()` between cases.

### Ports

`8080` Firestore · `9099` Auth · `5001` Functions · `4000` UI.

If a port is busy, change `firebase.json` **and** `FirebaseEmulatorPorts` in
`../lib/core/firebase/firebase_emulators.dart` together.

> **Cloud Messaging is not emulatable.** The Firebase Emulator Suite has no FCM
> emulator, so push delivery cannot be exercised locally and `firebase_messaging`
> is not wired to the emulators. FCM behaviour must be verified on a real device
> against a real project in Phase 4.

---

## Deploying against a real project

These commands require an authenticated account and a real project, and were
**not** run when this foundation was created.

```bash
cd kam
firebase login
firebase use --add                  # add your dev/prod project aliases
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

Then supply that project's client identifiers to the Flutter build via
`--dart-define` (see `../docs/architecture/FIREBASE_ARCHITECTURE.md` §3).

**Never** commit a service-account key, an Admin credential, or an `.env` file
containing secrets.
