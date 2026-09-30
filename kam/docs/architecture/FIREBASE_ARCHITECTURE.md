# Firebase Architecture — As Built

This document describes the current client and Firebase configuration. Earlier
Phase 3 setup assumptions remain in historical reports and ADRs; they do not
describe the current configured project. See
[`../PHASE_28_COMPLETION_REPORT.md`](../PHASE_28_COMPLETION_REPORT.md) for the
current verification state.

## Services and boundaries

| Service | Current use |
| --- | --- |
| Firebase Authentication | Email/password registration and sign-in; authenticated UID is the identity. |
| Cloud Firestore | User profiles/preferences, pairing codes, pairs/consent/sharing, device state/location, rules, interpretations, and owner-scoped events/notification records. |
| Firestore Security Rules | Backend authorization boundary; validates identity, pair membership, mutual consent, pause/revoke state, category sharing, ownership, schema, and timestamps. |
| Firebase Emulator Suite | Used by the JavaScript Rules suite with `demo-kam`; should be used for isolated development. |
| Local Android notifications | Native Android notification channel and MethodChannel; no FCM sender or remote push service. |
| Cloud Functions, Cloud Run, Scheduler, Pub/Sub, Firebase Admin | Not used; prohibited by the Spark-only architecture. |
| Analytics, Crashlytics, Remote Config, Storage | Not configured in the app. |

Client-side authorization logic is not a replacement for Firestore Security
Rules. The client observes state and requests operations; Rules decide whether
each remote read/write is authorized.

## Firebase initialization

`AppBootstrap.run()` calls `FirebaseBootstrap.initialize()` with generated
FlutterFire options enabled. The checked-in `lib/core/firebase/firebase_options.dart`
and local `.firebaserc`/`firebase.json` currently identify project
`gendersocialapp`. There is no separate development/production Firebase project
selection in the application. **The intent of this project as a production
environment is unconfirmed.** The project ID in source is configuration, not
proof of Firebase Console ownership, plan, enabled providers, database state, or
deployment status.

`APP_ENV` selects the app environment/logging policy, not the Firebase project.
Release defaults to production-safe logging, but generated Firebase options
still target `gendersocialapp`. A normal debug `flutter run` can therefore use
that same remote project unless emulator configuration is explicitly supplied.
Do not use real accounts or data for development without confirming the target.

Complete `FIREBASE_*` Dart defines override generated options. If any but not all
required client identifiers are supplied, initialization fails closed rather
than falling back to generated options. Release builds reject emulator
configuration. Client Firebase identifiers are not privileged server secrets;
never bundle Admin/service-account credentials, private keys, or server FCM
credentials.

`google-services.json` is ignored by Git and not required by this Gradle setup:
the Google Services Gradle plugin is not applied, and Android initialization
uses generated Dart options. A local Firebase Android client file exists in this
workspace and includes registrations for `com.example.kam` and `com.aj.kam`;
the current Android Gradle `applicationId` and namespace are `com.aj.kam`.

## Safe local emulator use

The Rules test file initializes test contexts with project ID `demo-kam`. Always
select that project explicitly for emulator commands so the CLI's current
`gendersocialapp` default is not used:

```powershell
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

The CLI starts Firestore on port 8080 by default. The app's emulator adapter uses
Firestore 8080 and Auth 9099. Start both for app-level authentication tests:

```powershell
firebase emulators:start --project demo-kam --only firestore,auth
```

For the Flutter app to connect, supply a complete dummy client configuration,
`FIREBASE_USE_EMULATORS=true`, and the correct host. `localhost` works for a
desktop target; Android Emulator normally reaches the host via `10.0.2.2`; a
physical Android device needs a reachable development-machine LAN address.

Example for Android Emulator:

```powershell
flutter run `
  --dart-define=APP_ENV=development `
  --dart-define=FIREBASE_PROJECT_ID=demo-kam `
  --dart-define=FIREBASE_API_KEY=demo-api-key `
  --dart-define=FIREBASE_APP_ID=1:000000000000:android:0000000000000000000000 `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=000000000000 `
  --dart-define=FIREBASE_USE_EMULATORS=true `
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

The emulator wiring is implemented in `lib/core/firebase/firebase_emulators.dart`.
There is no FCM emulator or app FCM integration. Rules tests use the actual
`firebase/firestore.rules` copy; it is byte-identical to root `firestore.rules`
at the Phase 28 audit.

## Firestore deployment files

`firebase.json` targets root `firestore.rules` and `firestore.indexes.json`.
Their mirrors in `firebase/` matched byte-for-byte at the Phase 27/28 source
audits. Firebase deployment has not been performed. Before a deployment, confirm
the intended project in Firebase Console, run emulator tests, and use an
explicit `--project <confirmed-project-id>` argument. Never rely on the current
CLI default for production deployment.

```powershell
firebase deploy --only firestore:rules --project <confirmed-project-id>
firebase deploy --only firestore:indexes --project <confirmed-project-id>
```

There is no Firebase Functions deploy target. The Spark-only architecture has no
trusted server, so no server-side rate limiting, scheduled cross-user cleanup,
or remote notification sender exists.

## Historical record

Phase 3 and the original ADR-007 recorded a period when no project configuration
was available and proposed demo-only/local settings. That is historical context.
The current source/CLI config described above supersedes those environment
claims. Phase 19's 114/114 Rules pass is historical; the Phase 26/28 emulator
suite could not be rerun in the current environment.
