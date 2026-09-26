# Spark-only migration — completion report

- **Date:** 2026-09-26
- **Phase:** architectural correction applied between Phases 4 and 5
- **Decision record:** [ADR-009](decisions/ADR-009-spark-only-no-cloud-functions.md)
- **Architecture:** [SPARK_ONLY_ARCHITECTURE.md](architecture/SPARK_ONLY_ARCHITECTURE.md)
- **Checklist:** [SPARK_COMPATIBILITY_CHECKLIST.md](SPARK_COMPATIBILITY_CHECKLIST.md)

## Summary

The application architecture no longer has a mandatory dependency that requires
a Firebase Cloud Billing account. It is designed for the **Spark (no-cost) plan**
using Authentication, Cloud Firestore and the Emulator Suite, plus client-side
domain logic and a local-notification boundary. No live Firebase project is
configured, so its actual console plan and production usage are not verifiable.

The migration was not a code deletion. **No Cloud Functions code ever existed** —
`functions/` was never scaffolded and neither `firebase-functions` nor
`firebase-admin` was ever a dependency. What existed was an *architectural
dependency*: ADR-002 assigned four responsibilities to Cloud Functions, and
Phase 3 had deliberately made pair activation **server-only** so that the rules
failed closed until a function was deployed. Left alone, pairing could never work
on Spark.

So the work was to make each former server operation **verifiable by Firestore
Security Rules instead of executable by a trusted process** — moving authority
from "a server that runs code" to "rules that check facts the client cannot
forge". No privileged capability was handed to the client.

---

## Corrected assumption

The Phase 3 report recorded a risk that reads as follows: *"Consent completion is
not enforced by rules (rules cannot verify both consent docs without a racing
cross-document read)"* — and concluded that a Function had to validate both
consents in a transaction.

**That premise was wrong.** A `get()` inside a Firestore rules evaluation is
resolved atomically with the write being authorized; there is no cross-document
race to lose. The rules can therefore verify the *other* member's consent
document directly, which is exactly what `bothConsentsGranted()` does. This
correction is what made a server unnecessary — the earlier assumption was the
single reason activation appeared to require one.

It is recorded here rather than quietly fixed because it changed a documented
architectural conclusion, and because the wrong version is still readable in the
Phase 3 report (now annotated as superseded).

---

## Removed

| Item | Notes |
| --- | --- |
| Cloud Functions as a planned dependency | Removed from ADR-002's row set, `FIREBASE_ARCHITECTURE.md` §7, `ARCHITECTURE.md` §16, both READMEs and the requirement mapping |
| The unused Functions emulator configuration | Removed the Functions emulator port from `firebase.json` and its unused Dart constant |
| Unused Cloud Messaging SDK dependency | Removed `firebase_messaging`: there is no client token registration or safe remote sender, so no app code needs the SDK |
| "Activation is server-side only" as a security stance | Replaced by the both-consent rule. This was the functional blocker |
| The assumption that `notifications` could only be written by the Admin SDK | Replaced by owner-written, rule-validated records |
| The assumption that pairing codes must be issued by a server | Replaced by client-generated codes with rule-enforced length, expiry and single use |

Nothing was deleted that still had a purpose: no Functions source, no Functions
dependency and no Functions deploy target ever existed, so there was no dead
configuration to strip.

---

## Migrated

| Old implementation (planned) | New implementation |
| --- | --- |
| **Cloud Function** — activate a pair by verifying both consents in a transaction | **Firestore Rules** — `bothConsentsGranted()` reads both `consents/{uid}` documents. Each consent can only be written by its own subject, so one member cannot manufacture the other's agreement. Strengthened further: `notPaused()` now also requires consent, so revoking consent stops partner reads immediately |
| **Cloud Function** — issue and validate an unguessable, expiring, single-use pairing code | **Client CSPRNG + Rules** — `Random.secure` generates ≥20 chars; rules enforce `20 ≤ length ≤ 64`, `expiresAt` within 1 hour and in the future, single-use redemption that changes only `usedByUserId`/`usedAt`, and **deny `list`** so outstanding codes cannot be harvested |
| **Cloud Function** — dispatch a notification | **Local notification boundary** — `RuleNotificationPlanner` decides (honouring `NotificationPreference`), and the per-user Firestore record is protected by `isSelf(uid)`. The default `LocalNotificationService` honestly reports unsupported until a platform plugin is implemented; no alert is claimed as delivered |
| **Cloud Function** — evaluate rules against device state | **Client rule engine** — `RuleEvaluator` (pure, deterministic, clock-injected) with a six-value outcome vocabulary that distinguishes *not matched* from *cannot tell* |
| **Cloud Function** — scheduled retention/deletion across users | **Deferred** (see below). Retention is policy plus ownership-scoped lazy cleanup; the client is never granted cross-user delete |
| **Server-side FCM sending** | **Deferred** (see below). No sending path, no credential |

New code:

- `lib/features/rules/domain/rule_evaluator.dart`, `rule_evaluation.dart`
- `lib/features/notifications/domain/rule_notification_planner.dart`
- `lib/core/notifications/local_notification_service.dart`
- `localNotificationServiceProvider` in `lib/app/providers.dart`
- `firebase/firestore.rules`: `consentDoc`/`consentGranted`/`bothConsentsGranted`,
  reworked pair update, new `pairingCodes` block, reworked `notifications` block
- `docs/architecture/SPARK_ONLY_ARCHITECTURE.md`, `docs/decisions/ADR-009-…`,
  `docs/SPARK_COMPATIBILITY_CHECKLIST.md`, this report, plus updates to
  `ARCHITECTURE.md`, `FIREBASE_ARCHITECTURE.md`, `FIRESTORE_DATA_MODEL.md`,
  `FIREBASE_SECURITY.md`, `ADR-002`, `REQUIREMENT_MAPPING.md`, the ADR index and
  both READMEs

---

## Deferred

Three capabilities genuinely require a trusted server. They are **documented as
unavailable rather than emulated**, because emulating them would mean shipping a
credential or granting the client authority over another person's data — both
prohibited.

| Capability | Why it needs a server | Impact | Target |
| --- | --- | --- | --- |
| Remote push to a partner's device | Needs an FCM credential held off-device | Alerts fire only while the recipient's app runs; otherwise the user sees last-known state with its age | Notification phase (needs Blaze or a non-Google sender) |
| Cross-user scheduled retention/deletion | Needs a privileged scheduler acting across users | Retention is policy + lazy ownership-scoped cleanup | Privacy phase (NFR-031, NFR-032) |
| Server-authoritative rate limiting | Rules cannot throttle | Pairing-code brute force is mitigated by entropy (≥20 chars, ≤1 h, unlistable), not by throttling | Documented limitation |

**Background execution** is also constrained and is not claimed: a Flutter app
cannot run arbitrary Dart continuously on either platform. The rule engine runs
while the process is alive; the product degrades to *last known state + timestamp
+ stale/unknown status* rather than pretending the engine kept running
(`FR-061`, `NFR-025`).

---

## Security

**What must never move to the client.** No secret exists in the mobile app, and
the migration added none. A value shipped to a device is available to whoever
holds the device, so `.env`, Dart constants, obfuscation, Remote Config, assets
and native configuration are all equivalent to publishing it. Specifically
excluded: Firebase Admin service-account credentials (`firebase-adminsdk`,
private keys, `"type": "service_account"`) and any FCM sending credential.

**Review performed.** A scan across `lib/`, `test/`, `firebase/`, `android/app/`
and `ios/Runner/` for `service.?account`, `private.?key`, `client.?secret`,
`admin sdk`, `firebase.?admin`, `cloud.?run`, `cloud scheduler`, `pub/sub`,
`FCM_SERVER`, `api.?secret` returned **only documentation comments and the
scanner's own pattern literals** — no credentials, and no reference to a billed
service. No secret is printed here, and none was found.

The scan is now a **test**, not a one-off: `test/architecture/spark_only_test.dart`
fails the build if a privileged credential marker appears where it could ship, or
if a Functions/Admin dependency or a `functions`/`extensions` deploy target is
added. Two further guards keep the security-critical design honest: the rules
must still contain `bothConsentsGranted`, the activation transition, the
`pairingCodes` block and the `notifications` block.

**No rule was weakened.** The change to `notPaused()` (requiring consent) is a
*strengthening*: previously an active pair with a live sharing category granted
reads even after consent was revoked. The notifications block previously denied
all client writes and now allows owner-scoped writes — a widening in principle,
but the collection is per-user, every write requires `isSelf(uid)`, content is
bounded and enumerated, the record cannot be backdated, and title/body/createdAt
are immutable. Crucially, a user still cannot write into anyone else's collection,
so nothing about another user's privacy changed.

---

## Firebase services

| Service | Used for | Spark-compatible |
| --- | --- | --- |
| Firebase Authentication | Identity only (email/password) | Yes |
| Cloud Firestore | Data **and** every authorization decision | Yes, within documented quotas |
| Emulator Suite | Firestore + rules tests + Auth locally | Yes (local, no project resources) |
| Firebase Cloud Messaging | Not used; the unused Flutter SDK dependency was removed | Not applicable |
| Cloud Functions / Cloud Run / Scheduler / Pub/Sub / Extensions | **Not used** | Not available on Spark |

---

## Billing

> **Architecture plan requirement: Spark — no Cloud Billing account is required.**

This is an architecture/configuration conclusion, not a claim about a deployed
Firebase project. No live project is configured, so no Firebase Console plan or
usage was inspected. Firebase documents Spark as requiring no payment
information, lists Authentication (most options) and FCM as no-cost products, and
provides a free Firestore quota; Cloud Functions and Extensions require Blaze.
See the official [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans),
[Cloud Functions billing FAQ](https://firebase.google.com/docs/functions/faq-and-troubleshooting),
and [Firestore billing documentation](https://firebase.google.com/docs/firestore/pricing).

In this repository, `firebase.json` has no `functions` or `extensions` deploy
target and the architecture test fails if one is added. Only Authentication and
Firestore are used by the app; emulator configuration is local-only.

The repository contains no real project alias or credentials that could be used
to inspect billing. No deployment or plan change was attempted.

---

## Testing

Commands actually executed, with their real results (final state):

| Command | Result |
| --- | --- |
| `flutter pub get` | ✅ `Got dependencies!` (after removing the unused FCM SDK) |
| `dart format --output=none --set-exit-if-changed .` | ✅ `126 files (0 changed)` |
| `flutter analyze` | ✅ `No issues found!` |
| `flutter test` | ✅ `All tests passed!` — **269 tests** (was 222) |
| `firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"` | ✅ **70 tests / 70 pass / 0 fail** (was 47), Firebase CLI 15.31.0 |
| `flutter build apk --debug` | ✅ `app-debug.apk` built |
| `flutter build ios` | ⚠️ **Not executed** — requires macOS/Xcode; unavailable on this Windows host |

`flutter pub remove firebase_messaging` removed the unused package and updated
`pubspec.lock` and the generated macOS plugin registrant. Its final platform
plugin setup step returned a Windows symlink-support error because Developer
Mode is off; the final `flutter analyze`, `flutter test`, and Android debug build
all passed after the dependency change.

New tests added:

- `test/unit/rule_evaluator_test.dart` — numeric and duration thresholds,
  boundary values, `hasRemainedInStateFor` (state *and* duration), state
  comparisons, disabled rules, cooldown (interpretation kept, no re-notify),
  insufficient data vs non-match, stale handling with and without opt-in,
  location-derived metrics, multi-rule evaluation, and the facts-vs-interpretation
  guarantees (percentage framed as a possibility; `isObjectiveFact == false`).
- `test/unit/rule_notification_planner_test.dart` — notify, every suppression
  reason, preference authority, and duplicate suppression.
- `test/unit/local_notification_service_test.dart` — the abstraction contract
  without any production notification service.
- `test/architecture/spark_only_test.dart` — the Spark invariants (§Security).
- 23 new emulator scenarios: both-consent activation (one-sided and denied
  consent rejected, both granted accepted), consent revocation stopping reads,
  pairing-code length/expiry/ownership/single-use/no-list/expiry-on-redeem, and
  owner-scoped notification create/read/deliver/delete with tampering rejected.

Not executed, and therefore **not** claimed: any real Firebase deployment, and
any end-to-end run against a live Auth/Firestore project (no project is
configured, and the FlutterFire plugins need a device).

---

## Limitations

1. **Local notification delivery is not implemented yet.** The tested boundary
   reports unsupported; the local platform plugin and notification flow remain
   work for the notifications phase. The migration does not claim an alert was
   delivered.
2. **No remote push.** No trusted sender exists under Spark. A user sees the
   last-known state and its age when the app is not observing updates.
3. **Background execution is not continuous** on Android or iOS. Rule evaluation
   happens while the process is alive; otherwise the UI shows last-known state
   with its age.
4. **No server-side rate limiting.** Pairing codes are protected by entropy and
   by `list` denial rather than throttling.
5. **Cross-user retention/cleanup is unenforced.** Ownership-scoped lazy cleanup
   only.
6. **Schema vocabulary mismatch, pre-existing.** The Dart pair lifecycle uses
   `requested/accepted/active/…` while the Firestore rules use
   `pending/active/paused/disconnected/revoked`. This was not introduced here and
   was not fixed here (Phase 5 owns the mapping), but it **will** cause a silent
   write rejection if Phase 5 sends the Dart enum names directly. Recorded as a
   risk below.
7. **iOS is unvalidated** on this Windows host.

## Status

**SPARK-ONLY MIGRATION STATUS: COMPLETE** — no mandatory Cloud Functions, Cloud
Run, Scheduler, Pub/Sub, Admin SDK, or server-secret dependency remains. Local
notification delivery, remote push, cross-user cleanup, and live-project quota
measurement remain explicit product/deployment limitations, not billing
dependencies hidden in the migration.

---

## Risks

1. **Pair-status vocabulary mismatch (act on this before Phase 5).** The Dart
   lifecycle (`PairLifecycleState`: `requested`, `accepted`, …) does not share
   names with the Firestore statuses the rules accept (`pending`, `active`,
   `paused`, `disconnected`, `revoked`). Phase 5 must map explicitly. If it sends
   enum names directly, pair creation and activation will be rejected by the
   rules with `permission-denied`, which looks like a rules bug but is a
   translation bug.
2. **Activation is now reachable from a client.** The invariant is enforced by
   the rules (both consent documents, server timestamp, immutable membership),
   and it is covered by four emulator scenarios — but it is a higher-traffic
   authorization path than before. Any future change to `consents` must be
   reviewed against the activation rule.
3. **A `get()` was added to a hot path.** `notPaused()` now reads the consent
   document, so every partner read performs one more document access. Firestore
   caches `get()` within a single rules evaluation, so the marginal cost is
   small, but this is the first thing to look at if read latency or rules cost
   becomes a concern (Spark has hard daily quotas).
4. **Rules cannot rate-limit.** A determined attacker can attempt pairing-code
   redemption repeatedly. Length (≥20 chars) and `list` denial make success
   infeasible rather than impossible; if this matters more later, it is another
   capability that would need Blaze.
5. **Notification coverage is honest but narrow.** Alerts are local-only, so a
   user who expects a phone alert while the app is closed will not get one. The
   UI must set that expectation rather than let a settings screen imply remote
   push.
