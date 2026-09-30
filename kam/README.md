# Know About Me (`kam`)

Know About Me is a private, consent-based Android app for two people who want a
limited view of each other's observed device state and user-defined
reassurance rules. It is not a messaging, social, or continuous tracking app.

## Scope and current status

- **Platform:** Android is the only supported target. iOS folders are project
  scaffolding, not supported or validated builds.
- **Users:** a pair has exactly two members; device visibility requires mutual
  consent and category-specific sharing.
- **Backend:** Firebase Authentication and Cloud Firestore with Firestore
  Security Rules. The architecture is intended for Firebase Spark; it has no
  Cloud Functions, Cloud Run, Scheduler, Pub/Sub, or custom backend.
- **Release status:** BLOCKED. Phase 26 end-to-end validation and Phase 27
  release validation could not complete. No production artifact or two-user
  device acceptance is claimed. See [Phase 26](docs/PHASE_26_COMPLETION_REPORT.md)
  and [Phase 27](docs/PHASE_27_COMPLETION_REPORT.md).

## Main capabilities

- Email/password authentication and user profile/preferences.
- Pairing codes, explicit mutual consent, pause/resume, and disconnect/revoke.
- Android battery/charging, network, display/activity, and foreground location
  observations, subject to Android permissions and lifecycle limits.
- Change-aware Firestore synchronization, freshness-aware partner state, and
  owner/pair/category authorization.
- Local rule evaluation, cautious interpretations, generic local notifications,
  and owner-scoped meaningful event history.

Unknown, stale, unsupported, and unavailable values remain distinct. Network
loss, app suspension, or lack of activity evidence never means a phone is off or
a person is inactive.

## Prerequisites

The repo records Flutter 3.44.8, Dart `^3.12.2`, Java bytecode target 17, and
Android min/compile/target API 24/36/36. These values have not all been verified
with a successful current build. Install Flutter, a compatible JDK and Android
SDK; install Node/npm and Firebase CLI only if running Firestore emulator tests.
See the [developer setup guide](docs/project/DEVELOPER_SETUP.md).

## Quick start

From this package directory:

```powershell
flutter pub get
flutter run
```

**Firebase target warning:** normal app bootstrap opts into the generated
`DefaultFirebaseOptions`, which currently point to `gendersocialapp`, even when
`APP_ENV=development`. `APP_ENV` selects logging/environment behavior; it does
not select a Firebase project. Do not use the default run for test data unless
you have confirmed that project is safe to use. For local work, configure the
Firestore/Auth emulators as described in the [developer setup guide](docs/project/DEVELOPER_SETUP.md).

## Quality and build commands

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Firestore Rules tests use the isolated `demo-kam` emulator project:

```powershell
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

These commands have not completed successfully in the current execution
environment. The latest outcome is in the [Phase 28 report](docs/PHASE_28_COMPLETION_REPORT.md).

## Production build

Release builds require protected signing material supplied with `KAM_RELEASE_*`
environment variables; no debug signing fallback is configured. Do not commit
the keystore or passwords. The permanent Android package ID and production
Firebase target still require confirmation. Follow
[production deployment](docs/deployment/PRODUCTION_DEPLOYMENT.md) only after
reviewing the [release checklist](docs/deployment/PRODUCTION_RELEASE_CHECKLIST.md).

## Documentation

Start with the [final project handover](docs/project/FINAL_PROJECT_HANDOVER.md)
and [documentation index](docs/README.md). They link architecture, security,
offline recovery, Android limits, testing, performance, observability, and
deployment documentation.
