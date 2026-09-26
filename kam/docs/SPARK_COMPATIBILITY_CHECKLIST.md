# Spark compatibility checklist

Verified against the repository at the end of the Spark-only migration
([ADR-009](decisions/ADR-009-spark-only-no-cloud-functions.md)). Each line names
the evidence, so the claim can be re-checked rather than trusted.

Result: **the architecture has no mandatory Cloud Billing dependency and is
designed for Firebase Spark.** No live Firebase project is configured, so the
project's current console plan and actual usage cannot be inspected.

| # | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| 1 | No Cloud Functions | ✅ | No `functions/` directory; no `firebase-functions` dependency; `firebase.json` has no `functions` block (asserted by `test/architecture/spark_only_test.dart`) |
| 2 | No Cloud Run | ✅ | No Cloud Run SDK, configuration, or deploy target; references in docs describe excluded services |
| 3 | No Cloud Scheduler | ✅ | No scheduler dependency or config; scheduled work is explicitly deferred (§6 of `SPARK_ONLY_ARCHITECTURE.md`) |
| 4 | No Pub/Sub | ✅ | No Pub/Sub dependency, topic or subscription |
| 5 | No Firebase Extension requiring Cloud Functions | ✅ | `firebase.json` declares no `extensions` block (asserted by the architecture test) |
| 6 | No server credentials in Flutter | ✅ | Credential scan across `lib/`, `test/`, `firebase/`, `android/`, `ios/` finds no service-account, private-key or FCM-server-key material |
| 7 | No Admin SDK credentials in Flutter | ✅ | No `firebase-admin` import or dependency; no Admin marker in the repo (asserted) |
| 8 | No hidden billing dependency | ✅ | Only Auth, Firestore and the Firestore emulator are configured; `pubspec.yaml` has no `cloud_functions`/`firebase_admin` (asserted) |
| 9 | Firestore usage stays within documented Spark quotas | ✅ design; live usage unverified | Current state is one overwritten document per (pair, owner); events are meaningful transitions only; `pairingCodes` cannot be listed. Current quotas and billing-only features are documented in `SPARK_ONLY_ARCHITECTURE.md` §7; there is no live project to measure |
| 10 | Authentication uses Spark-compatible functionality | ✅ | `firebase_auth` with email/password only; no Admin SDK, no blocking functions, no custom claims minted server-side |
| 11 | FCM usage remains Spark-compatible | ✅ | No FCM SDK, token registration, sending path, or FCM server credential is present. Remote push is deferred |
| 12 | Local notifications used where server-side triggering is unavailable | ⚠️ boundary ready | `LocalNotificationService` + `RuleNotificationPlanner` are tested; the default implementation reports `isSupported == false`. Platform delivery is deferred to the notifications phase |
| 13 | Background limitations documented | ✅ | `SPARK_ONLY_ARCHITECTURE.md` §4 (notifications) and §6 (deferred); `PLATFORM_CAPABILITIES.md` for per-platform reality |
| 14 | Security Rules enforce authorization | ✅ | `firebase/firestore.rules`, default-deny, verified by 70 emulator scenarios |
| 15 | Client-side logic does not replace authorization | ✅ | Evaluation and notification planning are local; every authorization decision is in the rules. Pair activation is gated on `bothConsentsGranted()` |
| 16 | Pair isolation remains enforceable | ✅ | `isMember`/`isActivePair` + per-category sharing + consent; covered by the rules suite (user isolation, pair isolation, disconnected/revoked) |
| 17 | No privileged operation moved to the client | ✅ | The two genuine **Category D** items (remote push, cross-user retention) are deferred, not delegated |

## Re-verifying

```bash
cd kam
flutter analyze
flutter test                       # includes test/architecture/spark_only_test.dart
firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"
```

The Spark-only invariants (items 1, 5, 6, 7, 8) are enforced by the test suite, so
a regression fails the build rather than relying on this checklist staying
accurate.

## What would require Blaze

Listed for completeness, so the boundary is explicit — none of these is
implemented, and adding one would change the project's plan requirement:

- any Cloud Function (including a scheduled one),
- remote push delivery to a partner's device,
- cross-user scheduled retention/deletion,
- Firebase Extensions that bundle Cloud Functions.
