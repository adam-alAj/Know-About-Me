# Phase 3 Completion Report — Firebase Project Setup & Backend Foundation

> **Historical record — partly superseded.** This report accurately describes Phase
> 3 as it stood. It is retained deliberately, because its Cloud Functions
> assumptions are the clearest explanation of *why* the Spark-only migration was
> needed. Every statement below that depends on a Cloud Functions project is now
> obsolete: see
> [ADR-009](decisions/ADR-009-spark-only-no-cloud-functions.md) and
> [SPARK_ONLY_ARCHITECTURE.md](architecture/SPARK_ONLY_ARCHITECTURE.md). In
> particular, claims 2 and the last two risk rows of §6 were **wrong about rules**:
> a rules evaluation can read sibling documents atomically with the write, so both
> consent documents *can* be verified without a Function.

- **Phase:** 3 of the phase plan in
  [`requirements/REQUIREMENT_MAPPING.md`](requirements/REQUIREMENT_MAPPING.md)
- **Date:** 2026-09-26
- **Status:** ✅ **COMPLETE** — with two explicitly documented external blockers
  (no real Firebase project; no Cloud Functions project) that were *not* faked.
- **Inputs reviewed first:** `Docs/SRS_DOC.md`, `docs/architecture/ARCHITECTURE.md`,
  `docs/platform/PLATFORM_CAPABILITIES.md`, `docs/requirements/REQUIREMENT_MAPPING.md`,
  `docs/PHASE_01_COMPLETION_REPORT.md`, `docs/PHASE_02_COMPLETION_REPORT.md`,
  `docs/decisions/ADR-001`…`ADR-006`, and the full `lib/` + `test/` tree.

---

## 1. Implemented

### FlutterFire integration

| Package | Version | Purpose |
| --- | --- | --- |
| `firebase_core` | `^4.15.0` | Firebase app initialization |
| `firebase_auth` | `^6.7.0` | Identity (Phase 4 implements the flow) |
| `cloud_firestore` | `^6.10.0` | Synchronized persistence |
| `firebase_messaging` | `^16.7.0` | Push delivery foundation |

New `lib/core/firebase/` (the only Firebase-aware part of `core/`):

| File | Responsibility |
| --- | --- |
| `firebase_config.dart` | Builds `FirebaseOptions` from `AppConfig`; `isConfigured` requires all four identifiers |
| `firebase_bootstrap.dart` | Single guarded `initialize()`; returns `bool`, never throws |
| `firebase_emulators.dart` | Emulator host/port wiring behind one flag |
| `firebase_error_mapper.dart` | Pure `FirebaseException`/`FirebaseAuthException`/`PlatformException`/`SocketException` → `AppException` + user-safe message |

`AppConfig` gained the Firebase identifiers and `useFirebaseEmulators`, and
`AppBootstrap` now calls `FirebaseBootstrap.initialize(...)` third in the startup
sequence. A failure logs a warning and the app continues offline.

### Firestore data model, indexes and Security Rules

- `firebase/firestore.rules` — default-deny; `users/{uid}` self-scoped;
  `users/{uid}/{settings,rules,fcmTokens,notifications}` owner-only (notifications
  writable only by the server, `read` flag owner-writable); `pairs/{pairId}` +
  `members`, `consents`, `sharing`, `devices`, `deviceState`, `location`,
  `interpretations`, `events` pair-scoped with per-category sharing checks.
- `firebase/firestore.indexes.json` — 7 composite indexes, each tied to a named
  future query (active pair by member; events by category/device/owner ordered by
  time; interpretations by owner; rules by enabled; notifications by unread).
- `firebase.json`, `.firebaserc` (`default` = local `demo-kam`), `firebase/package.json`.

### Emulator workflow and rules tests

- `firebase/test/firestore.rules.test.js` — **31 scenarios** run against the
  emulator with the real rules loaded, using `@firebase/rules-unit-testing`.
- `firebase/README.md` — install, run tests, start emulators, reset data, deploy.

### Client-safe configuration

Firebase is configured with explicit `FirebaseOptions` from `--dart-define` values
rather than a committed `google-services.json`. Consequences:

- the Android debug build needs **no** Google Services Gradle plugin and no
  project-specific config file,
- the repository contains **zero** Firebase credentials,
- supplying four values points the same binary at a real project, and
- omitting any one of them makes `isConfigured` false → the app runs offline and
  logs a warning instead of connecting to the wrong project.

### Documentation

`docs/architecture/FIREBASE_ARCHITECTURE.md`, `FIRESTORE_DATA_MODEL.md`,
`FIREBASE_SECURITY.md`, `docs/decisions/ADR-007-firebase-integration.md`,
`firebase/README.md`, and updates to `ARCHITECTURE.md` §3/§4/§5/§8/§14/§16/§17/§19,
`docs/decisions/README.md`, `kam/README.md` and the root `README.md`.

---

## 2. Architecture decisions

| Decision | Record |
| --- | --- |
| `FirebaseOptions` from `--dart-define`; no `google-services.json`; partial config fails closed | ADR-007 §1–2 |
| Firebase initialization is one guarded bootstrap call, failure-tolerant | ADR-007 §2 |
| Emulator Suite is the default local backend (`demo-kam`, `demo-` prefix) | ADR-007 §3 |
| Firebase confined to `core/firebase/` + feature `data/` layers, **enforced by a test** | ADR-007 §4 |
| Sharing lives at `pairs/{pairId}/sharing/{userId}`, re-read by rules per request; enforced on write and re-checked on read | ADR-007 §5 |
| Privileged transitions (`pairs.status = active`) are server-only; rules fail closed until a Function exists | ADR-007 §6 |
| Rules are proven by emulator tests, never assumed | ADR-007 §7 |

Sections §3 (environment strategy), §6 (ownership), §7 (pair isolation),
§8 (FCM), §9 (Functions), §10 (offline), §11 (cost), §12 (timestamps) of
`FIREBASE_ARCHITECTURE.md` / `FIRESTORE_DATA_MODEL.md` record the reasoning in full.

Phase 1/2 architecture was preserved. The only additions were
`lib/core/firebase/`, the Firebase config files, and one new architecture rule.

---

## 3. Tests

| Suite | Count | Coverage |
| --- | --- | --- |
| Flutter (`flutter test`) | **114** | 91 from Phases 1–2, plus Firebase config and error mapping |
| Firestore Security Rules (emulator) | **31** | Required scenarios below |

New Flutter tests:

- `test/unit/firebase_config_test.dart` — options assembly per platform, all four
  identifiers required, partial config fails closed, emulator flag defaults.
- `test/unit/firebase_error_mapper_test.dart` — permission-denied, unavailable,
  not-found, auth-expired/invalid-credential, network, unknown; asserts that no
  raw SDK text reaches the user-facing message.
- `test/unit/app_startup_test.dart` — extended: bootstrap resolves config and does
  **not** throw when Firebase is unconfigured.
- `test/architecture/domain_purity_test.dart` — extended: a Firebase SDK import
  outside `core/firebase/` or a feature `data/` layer fails the build.

### Rules scenarios (all 31 pass)

**Unauthenticated** (2): cannot read application data; cannot create a pair.

**User isolation** (7): cannot read another user's profile; partner-scoped data
never exposes home coordinates; cannot read another user's device state; can read
their own private data; cannot read an unrelated pair or its subcollections; can
list only the pairs they belong to; a non-member cannot read shared state.

**Sharing and category gating** (7): an active member can read the categories the
owner shares; the owner can always read their own state; location is not readable
unless shared; location becomes readable once shared; pausing sharing hides the
partner's data; the owner cannot store a category they have not shared; the owner
cannot write their location while location sharing is off.

**Pair lifecycle** (4): a pending (unauthorized) pair grants no access; a
disconnected member loses access; a revoked pair grants no access; a client cannot
activate a pair by itself (plus: membership cannot be changed by a member; a member
cannot raise the owner's sharing).

**Unauthorized writes** (5): cannot write another user's profile; a sharing
document cannot contain an unknown category; history events are append-only; a
member cannot record an event as another user; notifications cannot be created or
deleted by a client; a user can only mark their own notification as read.

**Facts vs interpretations** (3): an interpretation must be flagged as
user-defined; cannot create one without sharing interpretations; interpretations
are immutable once created.

---

## 4. Validation (actual commands and results)

| Command | Result |
| --- | --- |
| `firebase --version` | `15.24.0` |
| `java -version` | OpenJDK `21.0.9` |
| `flutter pub get` | ✅ resolved (`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`) |
| `flutter analyze` | ✅ `No issues found! (ran in 3.4s)` |
| `dart format --output=none --set-exit-if-changed .` | ✅ `91 files (0 changed)` |
| `flutter test` | ✅ `All tests passed!` — **114 tests** |
| `firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"` | ✅ `# tests 31 / # pass 31 / # fail 0` |
| `flutter build apk --debug` | ✅ `Built build\app\outputs\flutter-apk\app-debug.apk` |
| `flutter build ios` | ⚠️ **Not executed — macOS/Xcode required**; on Windows the `ios` subcommand is unavailable |
| `firebase deploy --only firestore:rules` | ⚠️ **Not executed** — requires an authenticated account and a real project; no project exists |
| `firebase emulators:start` (all services) | ⚠️ **Not executed** — Foreground process; the equivalent `emulators:exec --only firestore` run proves the config |

The emulator run loads the real `firestore.rules`, so the 31 passes are evidence
about the shipped rules rather than a separate test copy.

---

## 5. Deferred (intentionally, by phase)

| Item | Phase |
| --- | --- |
| Authentication flow (sign-up, sign-in, session restore, redirect guard) | 4 |
| Profile document read/write, user preferences | 4 |
| FCM token registration and permission request | 4 (foundation documented now) |
| Pairing and mutual-consent workflow; pair activation | 5 |
| Device monitoring collectors (Android/iOS) | 6 |
| Location collection and distance from home | 7 |
| Rule evaluation engine | 8+ |
| Notification dispatch | 8+ |
| Event-history UI | 9+ |
| ~~Cloud Functions project (rule evaluation, notification triggers, cleanup)~~ — **ruled out**; superseded by ADR-009 | — |

No rule, provider or widget for any of the above was created "for shape".

---

## 6. Known limitations

1. **No real Firebase project is connected.** No project id, API key, app id or
   sender id exists in this environment, and inventing them was forbidden. The
   foundation is complete and secure; the remaining step is purely operational
   (`FIREBASE_ARCHITECTURE.md` §5).
2. **~~No Cloud Functions project, so `pairs.status` cannot reach `active`.~~** —
   **superseded.** Under the Spark-only architecture there is no Functions project
   and none is planned; the rules instead gate activation on both consent
   documents. `pairs.status` *can* now reach `active`, without a server and
   without permitting an insecure shortcut.
3. **iOS build not validated** — Windows host, no Xcode.
4. **No production deployment was performed or claimed.** Rules deploy, index
   deploy and project creation are documented, not executed.
5. **`google-services.json` is not used.** A future operator must transcribe the
   Firebase console app registration into `--dart-define` values.
6. **The emulator rules tests require Node + Firebase CLI + a JDK**, so they are a
   separate command from `flutter test` and are not part of the Flutter test run.
7. **No App Check.** Deliberate: it needs a real project and reCAPTCHA/Play
   Integrity registration; recorded as a recommended hardening step
   (`FIREBASE_SECURITY.md` §9.4).
8. **FCM cannot be tested locally.** The Emulator Suite has no Cloud Messaging
   emulator, so `firebase_messaging` is not wired to the emulators and push
   delivery cannot be exercised without a real project and device. This is why no
   `messaging` emulator port is declared (`FIREBASE_ARCHITECTURE.md` §3).

---

## 7. Risks

| Risk | Impact | Mitigation / status |
| --- | --- | --- |
| Sharing gates read a second document (`get()`), adding billed reads | Cost at scale | Accepted and bounded: ≤2 document lookups per partner read; recorded in the cost model |
| A client could write unauthorized data if rules drift | Privacy breach | 31 rules tests; rules changes must keep them green; rules are the only authorization path |
| ~~Pair activation depends on a Function that does not exist yet~~ | Phase 5 dependency | **Resolved** by ADR-009: activation is gated by the rules on both consent documents |
| `demo-kam` could be mistaken for a deployable project | Accidental deploy attempt | `.firebaserc` uses the reserved `demo-` prefix; deploy steps require an explicit `firebase use --add` |
| Emulator ports may collide on a busy machine | Local dev friction | Ports documented in one place (`firebase.json` + `FirebaseEmulatorPorts`); ports must change together |
| Location retention is defined in policy but not yet enforced | Long-term privacy | Retention documented per collection in `FIRESTORE_DATA_MODEL.md` §10; a scheduled cleanup Function is scheduled with Phase 5+ |
| ~~Consent completion is not enforced by rules (rules cannot verify both consent docs without a racing cross-document read)~~ | — | **Assumption corrected.** This premise was wrong: a rules `get()` is evaluated atomically with the write, with no race. `bothConsentsGranted()` now enforces exactly this, covered by four emulator scenarios (ADR-009) |
| Firestore offline cache can look current | Misleading UI | `FreshnessIndicator` + `DataPresentation` already refuse to present stale data as current (`ARCHITECTURE.md` §12); Phase 6 wires real timestamps |

---

## 8. Secret and configuration review

Repository-wide scan for private keys, `AIza…`-shaped API keys, service-account
artifacts, `admin.initializeApp`, and PEM headers:

```
grep -rIn -E "BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY|AIza[0-9A-Za-z_-]{30,}|
  service_account|serviceAccount|admin\.initializeApp|-----BEGIN" \
  --include="*.dart" --include="*.json" --include="*.yaml" --include="*.js" \
  --include="*.md" --include="*.rules" .
```

Result: **no matches** (excluding `node_modules` and lockfiles).

`kam/.gitignore` additionally blocks `*.env`, `*.pem`, `*.jks`,
`service-account*.json` and `node_modules/`; verified with `git check-ignore`.

**Client-safe** (present, by design): Firebase project id, API key, app id,
messaging sender id — these identify a project and are not credentials.
**Absent by design:** Firebase Admin service-account keys, FCM server keys, any
private API key. Nothing was exposed, so no rotation is required.

---

## 9. Next phase

**Phase 4 — Authentication & User Profile** can start immediately:

1. Implement `AuthRepository` against `FirebaseAuth` (register, sign in, sign out,
   session restore) in `lib/features/auth/data/repositories/`, replacing
   `UnauthenticatedAuthRepository`; keep returning `Result` and map SDK errors
   through `FirebaseErrorMapper`.
2. Build the sign-in/sign-up/onboarding screens and wire the `redirect` guard into
   `createAppRouter()` — the route names are already reserved in `AppRoutes`.
3. Implement the `users/{uid}` profile read/write and preferences
   (`FIRESTORE_DATA_MODEL.md` §3); the rules for it already exist and are tested.
4. Register the FCM token at `users/{uid}/fcmTokens/{tokenId}` and handle refresh
   deletion (`FIREBASE_ARCHITECTURE.md` §8).
5. Supply the real project's four identifiers via `--dart-define` in the dev run
   configuration, and optionally run Phase 4 integration work against the emulators.

No re-architecture is required: the DI seams, routing guard hook, result/error
handling and rules are already in place.
