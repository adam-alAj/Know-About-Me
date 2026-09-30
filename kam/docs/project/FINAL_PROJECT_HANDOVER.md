# Know About Me — Final Project Handover

**Repository:** `kam`  
**Product platform:** Android only  
**Project readiness:** BLOCKED  
**Documentation date:** 2026-09-30

This is the main maintainer handover. It describes the current source/configuration
and preserves validation gaps. It does not certify production readiness. See the
[documentation index](../README.md), [Phase 26](../PHASE_26_COMPLETION_REPORT.md),
[Phase 27](../PHASE_27_COMPLETION_REPORT.md), and
[Phase 28](../PHASE_28_COMPLETION_REPORT.md).

## 1. Project overview and scope

Know About Me is a private, consent-based reassurance application for two people
who want to selectively share observations about device state. Each pair is
limited to two users. The product supports authentication, pairing and mutual
consent, category sharing, Android device observations, partner state, user
rules/interpretations, local notifications, event history, pause/resume, and
disconnect/revocation.

The application is not a public SaaS, social network, messaging product, or
continuous location tracker. The client observes only supported Android signals;
users choose which supported categories their partner may see. Unknown, stale,
denied, and unsupported values are preserved instead of guessed.

## 2. Architecture

```text
Android OS / Firebase SDK / local preferences
                  ↕
       Platform adapters and repositories
                  ↕
        Domain models and services
                  ↕
       Riverpod providers / app state
                  ↕
 Flutter presentation, router, and screens
```

Feature code is under `lib/features/<feature>/{domain,data,presentation}`;
shared app composition and services are under `lib/app/` and `lib/core/`.
Riverpod composes providers and owns scoped stream lifetimes. Repositories
separate domain interfaces from Firestore/shared-preference implementations.
Domain/rule logic avoids Flutter widgets and Firebase SDK dependencies.

Key areas:

- `auth`: Firebase email/password identity, profile/preferences, session routing.
- `pairing`: code creation/redemption, two-member pair, consent and lifecycle.
- `privacy`: independent owner sharing controls and pause state.
- `device_state`: Android adapters, normalization, freshness, synchronization,
  partner projection, and lifecycle ownership.
- `rules`: rule persistence/building, pure evaluation, interpretation and alert
  eligibility.
- `history`: minimized meaningful events, local cache and Firestore repository.
- `core/firebase`, `core/storage`, `core/logging`, `core/notifications`: backend,
  sensitive cache cleanup, safe diagnostics and OS notification boundary.

See [Architecture](../architecture/ARCHITECTURE.md),
[Firebase architecture](../architecture/FIREBASE_ARCHITECTURE.md),
[Firestore data model](../architecture/FIRESTORE_DATA_MODEL.md), and the source
tree for detail. The early architecture foundation document is historical; this
handover and the implementation are the as-built reference.

## 3. Important data flows

### Authentication and profile

```text
User -> Firebase email/password -> authenticated UID -> profile/preferences
     -> auth-scoped providers and protected routes
```

Profile documents are owner-scoped. Partner display information is copied into
pair-scoped membership documents only as designed; partner access to private
`users/{uid}` profiles is not granted.

### Pairing and consent

```text
User A creates short-lived code -> User B redeems -> pending two-member pair
     -> each user records explicit consent -> both granted -> active pair
```

A code alone grants no device access. Pair membership remains immutable after
creation. Consent, pause, disconnection/revocation and sharing state are checked
by Firestore Rules. Rules are the authority even when client code optimistically
updates UI.

### Device state and synchronization

```text
Android API -> MethodChannel adapter -> normalized observations + timestamps
 -> local state -> sharing/active-pair gate -> coalesce/change detection
 -> Firestore current-state documents -> authorized partner stream -> UI
```

The source uses event-driven/device lifecycle collection and change-aware writes;
the Phase 24 report documents a 3-second coalescing window, payload
deduplication and bounded transient retry. No current runtime cost/battery
measurements were collected. One missing network path is not proof the phone is
off.

### Rules, interpretation, alerts and history

```text
authorized partner observations -> freshness-aware rule evaluation
 -> fact/interpretation presentation -> eligibility/preferences/cooldown
 -> local Android notification attempt -> meaningful event/history
```

The evaluator is client-side and deterministic; Firestore Rules protect what
inputs and writes the client can access. User-configured or heuristic
interpretations are not validated statistical predictions. A rule match does
not prove notification delivery.

## 4. Firebase and environments

The app uses Firebase Authentication and Cloud Firestore. Firestore Security
Rules are the backend authorization boundary; no trusted custom server exists.
The repository is designed for Firebase Spark and intentionally has no Cloud
Functions, Cloud Run, Scheduler, Pub/Sub, Admin SDK, FCM sender, or other paid
backend service.

Current `firebase.json`, `.firebaserc`, generated FlutterFire options, and local
ignored Android client configuration point to `gendersocialapp`. No separate
development/production project map exists and the project's production intent,
plan, Auth provider settings, database state, ownership, and actual deployed
Rules/indexes were not confirmed. The app bootstrap uses generated options by
default, including in a normal debug run. `APP_ENV` does not switch Firebase
projects. Treat default app runs as capable of reaching the configured remote
project.

Rules tests explicitly use the local `demo-kam` project. Always pass
`--project demo-kam` to emulator test/start commands; do not let the CLI inherit
the current `gendersocialapp` default. For app-level emulator use, provide a
complete dummy `FIREBASE_*` set, `FIREBASE_USE_EMULATORS=true`, and an emulator
host appropriate to the target (Android Emulator: `10.0.2.2`; physical device:
reachable development host IP). Emulator ports are Firestore 8080 and Auth 9099.

`firebase.json` deploys root `firestore.rules` and `firestore.indexes.json`. The
copies under `firebase/` matched byte-for-byte at the Phase 27/28 audit. Use
explicit project IDs for deployment only after confirming the target. Client
Firebase options/API identifiers are not privileged secrets. Never put Admin
credentials, service-account keys, private keys or server notification
credentials in the app or repository.

## 5. Security and privacy

The authorization chain is:

```text
Firebase Auth UID -> Firestore Rules -> pair membership -> mutual consent
 -> pair active/not paused -> owner category sharing -> resource ownership
```

The Rules enforce the two-member invariant, membership and ownership, independent
sharing categories, location gating, pair lifecycle, field allowlists, typed and
bounded data, server-authoritative security timestamps, immutable identity
fields, append-only records where specified, and monotonic state versions. Client
checks improve the UI but cannot grant access. Device IDs are identifiers, not
authorization evidence.

User A cannot access unrelated pair B by virtue of being authenticated. Histories
and private data remain owner-scoped; partner queries are pair-scoped and
category-authorized. Sign-out/session loss clears protected local history,
location and activity observations via `SensitiveLocalData`; opaque device ID
and sync version are deliberately retained and are not authorization state.

Location requires both Android OS permission and owner sharing consent. Current
permissions are foreground coarse/fine only. Source does not implement messages,
call contents, keystroke capture, microphone/camera capture, installed-app
inventory, Accessibility Service, or notification-content monitoring. Source
declares no background location permission or background location service.
Device state, location/home data, and alert metadata are privacy-sensitive even
when stored locally or shown only to the owner.

Important confirmed architectural limits: no server-side rate limiting, global
pair ID uniqueness enforcement, App Check, cross-user scheduled retention,
server push, or instant offline revocation awareness. History already written is
not category-retracted when sharing is later disabled; current access remains
gated as documented in [Security and authorization](../security/SECURITY_AND_AUTHORIZATION.md).

## 6. Device-state semantics

```text
UNKNOWN != FALSE                     UNSUPPORTED != FALSE
STALE != CURRENT                     ERROR != FALSE
PERMISSION DENIED != UNSUPPORTED     NO NETWORK != PHONE OFF
NO FIRESTORE UPDATE != PHONE OFF     BACKGROUND SUSPENSION != PHONE OFF
SCREEN OFF != USER SLEEPING          NO ACTIVITY != USER INACTIVE
OS PERMISSION != PARTNER SHARING     CACHE != CURRENT AUTHORIZATION
```

Values carry observation/freshness where supported. Examples:

- Say “Location updated 2 hours ago,” not “currently at home,” for a stale fix.
- Say “Device unavailable; last seen 35 minutes ago,” not “phone powered off.”
- Say “Activity could not be observed,” not “person is inactive.”
- A permission denial means collection was denied; unsupported means the
  platform/capability does not provide that signal.

See [offline/stale semantics](../reliability/OFFLINE_STALE_DATA_AND_RECOVERY.md)
and [Android capabilities](../platform/PLATFORM_CAPABILITIES.md).

## 7. Rule engine and notification boundary

Rules are user-owned, versioned conditions over supported categories/metrics.
Evaluation consumes an authorized partner state and freshness evidence; unknown,
unavailable, denied and unsupported inputs are indeterminate rather than false.
Stale handling follows the rule's configured policy and remains labelled stale.
Facts and interpretations are kept separate; heuristic/user-defined
probabilities are not science-backed predictions.

The alert planner applies enabled/new-match, freshness, preference and cooldown
rules, then attempts a local Android notification. Lock-screen copy is generic;
the app does not provide remote FCM delivery. Android tap behavior carries a rule
ID launch extra but has not been device-validated; authorization must still be
derived from the current authenticated/pair scope. Rule match is not delivery.
See [notifications](../notifications/NOTIFICATIONS_AND_RULE_ALERTS.md).

## 8. Offline and recovery

Firestore SDK cache/queued writes are not current authorization. Security Rules
re-evaluate requests when sent against current pair, consent, pause, sharing and
ownership documents. Permission/authorization failures are not retried blindly;
transient device-state publishing uses a bounded retry policy and latest-state
coalescing. Pair/auth/sharing providers own listeners and scope recovery.

A fully disconnected device cannot know remote revocation immediately. Cached
data may remain on device with its original observation age until reconnect; the
UI must not treat it as current. After reconnection, listeners reattach, current
authorization gates reads/writes, state freshness is recalculated and eligible
rules may run on refreshed state. This path has not been validated end-to-end.

## 9. Local data and cache

SharedPreferences contains a bounded history cache (up to 500 events/180 days),
the last location observation, activity/online observation times, opaque device
identity and sync version. Sensitive observations are cleared on sign-out/session
end; identity/version are deliberately preserved. Local history reads require
the current owner UID. Android backup and device transfer are disabled/excluded
for app-private data. Cache age is provenance, not permission.

## 10. Testing and evidence

| Area | Current evidence/status |
| --- | --- |
| Unit/widget/architecture tests | Broad tests exist. Current `flutter test` has not completed in the available environment. Historical Phase 19 result: 617/617; later supplied run: 662/663 with a privacy timeout before a source fix; fix not rerun. |
| Analyzer | Historical clean Phase 19 result only. Later user-supplied runs found infos that were corrected in source; current analyzer run is BLOCKED. |
| Firestore Rules | Phase 19 historically records 114/114. Current suite not rerun; Firebase CLI/Node/npm unavailable. |
| Integration/two-user | No dedicated `integration_test/` suite was found; two-user journey NOT TESTED. |
| Android permissions/lifecycle | Device/emulator checks BLOCKED; ADB cannot initialize its user directory. |
| Offline/revocation | Source/docs describe behavior; offline two-client revocation NOT TESTED. |
| Release smoke/build | Phase 27 release build stalled; no artifact/device install. |

Do not treat test existence, source inspection, or historical counts as current
acceptance. See [test strategy](../testing/TEST_STRATEGY.md), [acceptance
matrix](../testing/END_TO_END_ACCEPTANCE_MATRIX.md), and the Phase 26/27 reports.

## 11. Setup, build and deployment

Use [developer setup](DEVELOPER_SETUP.md) for prerequisites, local emulator
configuration, and app/test commands. Use [production deployment](../deployment/PRODUCTION_DEPLOYMENT.md)
and the [release checklist](../deployment/PRODUCTION_RELEASE_CHECKLIST.md) for
Firebase safeguards, signed builds, install/smoke process and rollback. Current
application ID and namespace are `com.aj.kam`, version is `1.0.0+1`, launcher label is
`Know About Me`, and the launcher image is the Flutter template icon. The package identity,
branding, distribution method and production Firebase target need confirmation.
Release signing requires environment-sourced keystore settings; no release
artifact was produced.

## 12. Troubleshooting and operations

See [troubleshooting and maintenance](TROUBLESHOOTING_AND_MAINTENANCE.md) for
safe diagnostic steps, emulator setup, auth/pair errors, permission state,
indexes, stale data, notifications, signing and operational review.

## 13. Do Not Change These Boundaries Casually

- Firestore Security Rules remain the authorization boundary; client checks do
  not replace them.
- Pair membership stays isolated and exactly two; mutual consent stays explicit.
- Each sharing category, especially location, remains independently authorized.
- Device IDs never become authorization evidence; server timestamps and
  immutable ownership fields keep their Rules semantics.
- Historical observation timestamps are not synchronization timestamps.
- `UNKNOWN`, `UNSUPPORTED`, `STALE`, `ERROR`, no network, background suspension,
  or screen-off are not converted into false/certain human or power-state claims.
- Cached data is not current authorization; reconnect and queued writes must be
  checked against current server state.
- Rule match does not imply notification delivery; notification tap does not
  grant access.
- Sensitive local data cleanup remains tied to session lifecycle and history
  remains owner-scoped.
- Firestore writes remain bounded/change-aware; do not add heartbeats or raw
  high-frequency telemetry without measured need and privacy review.
- Preserve Spark-only constraints unless the product owner intentionally changes
  the backend architecture and validates its costs/security.

## 14. Known limitations and final status

- Android background collection is best effort; no guaranteed continuous/24-hour
  monitoring or reliable physical power-off detection.
- Location is foreground-only and may be reduced, stale, denied or unavailable.
- Local notification delivery depends on Android permissions/channel/settings.
- No remote push, App Check, server-side rate limiting, global code uniqueness
  or scheduled cross-user cleanup.
- Offline clients cannot immediately learn remote revocation.
- No password-reset/account-deletion flow was found in the app source.
- Production project intent, permanent package identity, branding, signing key,
  distribution channel and deployed Firebase state remain unconfirmed.
- Current automated validation, Android install, release smoke and two-user
  acceptance are blocked/unverified.

**Final project status: BLOCKED.** This means validation/release readiness is not
established; it does not mean the implemented feature surfaces were all proven
to fail. The authoritative next actions are the unresolved gates in the Phase
26/27 reports and release checklist.
