# Spark Compatibility Checklist — Current Source

The architecture has no mandatory Cloud Billing dependency and is designed for
Firebase Spark. Source/CLI configuration points to `gendersocialapp`, but its
Firebase Console plan and usage were not verified. Do not infer plan status from
source configuration. No Firebase deployment occurred in Phases 26–28.

| Requirement | Current status | Evidence / limit |
| --- | --- | --- |
| No Cloud Functions | PASS (source/config) | No functions directory/dependency/target; architecture test asserts exclusion. |
| No Cloud Run, Scheduler or Pub/Sub | PASS (source/config) | No SDK or deploy target; no serverless infrastructure. |
| No paid extension/hidden backend | PASS (source/config) | `firebase.json` has Firestore config only; no extensions, Storage, Analytics or Crashlytics configured. |
| No server credentials in Flutter | PASS (source audit) | No Admin SDK or service-account/private signing material in app source; do not include Firebase Admin or server FCM credentials. |
| Auth is Spark-compatible | Implemented; remote setup NOT TESTED | `firebase_auth` email/password; console provider settings unverified. |
| Firestore usage model | Designed for Spark; live usage NOT TESTED | Current state is overwritten/coalesced; events are meaningful; no runtime reads/writes or quota metrics available. |
| Local notifications | Implemented in Android source; runtime NOT TESTED | Native MethodChannel notification; no FCM/token/remote sender. OS permission/channel may suppress delivery. |
| Rules enforce authorization | Source implemented; current emulator tests BLOCKED | Default-deny root Rules mirror `firebase/firestore.rules`; Phase 19 historically records 114/114; current emulator run blocked. |
| Client logic does not replace Rules | PASS (source architecture) | Pair, consent, sharing, ownership and access are checked in Firestore Rules. |
| Pair isolation and mutual consent | Source implemented; runtime NOT TESTED | Membership, two-person pair and both-consent activation checks are in Rules; Phase 26 two-user test blocked. |
| Cross-user server operations | Deferred | No remote push sender or scheduled cross-user cleanup; no privileged operation was moved into client authority. |

## Emulator and test commands

Rules fixtures use `demo-kam`; explicitly choose it so the CLI does not use the
repository's `gendersocialapp` default:

```powershell
flutter analyze
flutter test
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

## Confirm before release

- Verify in Firebase Console which project and plan are in use. The repository
  config alone does not prove Spark plan or production intent.
- Check current quotas/usage in Firebase Console; no live usage data was
  inspected here.
- Keep the application free of Cloud Functions, Cloud Run, Scheduler, Pub/Sub,
  Admin SDK, paid extensions and server FCM credentials unless the product owner
  intentionally changes the Spark-only architecture and reviews the implications.
