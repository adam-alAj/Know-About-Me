# Firestore Rules Test Project

This directory contains the Node test package and mirrored Rules/index files.
The executable Rules tests use Firebase Emulator Suite with project ID
`demo-kam`; they do not require a production account when run against the
emulator. Always pass `--project demo-kam`: the repository `.firebaserc` default
is `gendersocialapp` and must not be used accidentally for emulator testing.

## Files and sources of truth

| File | Purpose |
| --- | --- |
| `../firebase.json` | Firebase CLI Firestore Rules/index deployment targets (root files). |
| `../.firebaserc` | CLI project default (`gendersocialapp`; production intent unverified). |
| `firestore.rules` | Mirror of root `../firestore.rules`; tests load this copy. |
| `firestore.indexes.json` | Mirror of root `../firestore.indexes.json`. |
| `package.json` / `package-lock.json` | Node test dependencies and `npm test` script. |
| `test/firestore.rules.test.js` | Emulator test setup with project ID `demo-kam`. |

The root Rules and index files are the deployment paths configured in
`firebase.json`. Mirror parity was checked during Phase 27/28. No production
Rules or indexes deployment is claimed.

## Prerequisites and test

Install Node.js/npm and Firebase CLI, then run from the Flutter package root:

```powershell
npm --prefix firebase ci
firebase --version
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

Test prerequisites include the Firebase Emulator Suite and a supported Java
runtime. The current environment did not have Node/npm or Firebase CLI available,
so current Rules test status is BLOCKED. Phase 19 historically reports 114/114
passing scenarios; this is not a current result.

## Run the app against local emulators

Start both services:

```powershell
firebase emulators:start --project demo-kam --only firestore,auth
```

Configure the Flutter app with complete dummy Firebase client options and
`FIREBASE_USE_EMULATORS=true`. For Android Emulator the host is normally
`10.0.2.2`; desktop uses `localhost`; physical devices use a reachable LAN IP.
See [`../docs/architecture/FIREBASE_ARCHITECTURE.md`](../docs/architecture/FIREBASE_ARCHITECTURE.md)
and [`../docs/project/DEVELOPER_SETUP.md`](../docs/project/DEVELOPER_SETUP.md).

The adapter uses Firestore port 8080 and Auth port 9099 (Firebase CLI defaults).
This project has no Functions emulator and no FCM integration. Emulator UI is
not configured by the repository.

## Deploying Rules/indexes

The repository's CLI default is `gendersocialapp`; its production intent is
unconfirmed. Never run deployment based on that default. First inspect and test
the root rules/indexes, confirm project ownership and environment in Firebase
Console, authenticate with the intended operator account, and pass an explicit
confirmed project ID:

```powershell
firebase deploy --only firestore:rules --project <confirmed-project-id>
firebase deploy --only firestore:indexes --project <confirmed-project-id>
```

These commands are instructions only and were not executed in Phases 26–28. Never
commit service-account keys, Firebase Admin credentials, private keys, or
environment secrets.
