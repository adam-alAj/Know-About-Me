# Phase 4 Completion Report — Authentication & User Profiles

- **Phase:** 4 of the phase plan in
  [`requirements/REQUIREMENT_MAPPING.md`](requirements/REQUIREMENT_MAPPING.md)
- **Date:** 2026-09-26
- **Status:** ✅ **COMPLETE** — with one explicitly documented verification gap
  (no real end-to-end run against the Auth emulator; see §6.1).
- **Inputs reviewed first:** `Docs/SRS_DOC.md`, `docs/architecture/ARCHITECTURE.md`,
  `AUTHENTICATION`-relevant parts of `FIREBASE_ARCHITECTURE.md`,
  `FIRESTORE_DATA_MODEL.md`, `FIREBASE_SECURITY.md`,
  `docs/requirements/REQUIREMENT_MAPPING.md`, the Phase 1–3 completion reports,
  `docs/decisions/ADR-001`…`ADR-007`, the whole `lib/` + `test/` tree, and
  `firebase/firestore.rules` + its tests.

---

## 1. Implemented

### Identity

| Piece | File |
| --- | --- |
| `AuthIdentity` (uid, email, verified) | `features/auth/domain/models/auth_identity.dart` |
| `AuthState` — sealed, six cases | `features/auth/domain/models/auth_state.dart` |
| `AuthRepository` contract (identity only) | `features/auth/domain/repositories/auth_repository.dart` |
| Firebase implementation (the only `FirebaseAuth` user) | `features/auth/data/repositories/firebase_auth_repository.dart` |
| Honest no-op for an unconfigured build | `features/auth/data/repositories/unavailable_auth_repository.dart` |
| State machine | `features/auth/presentation/providers/auth_controller.dart` |

Registration, sign-in, sign-out and session restoration all work through the
repository boundary; no widget or domain class imports a Firebase package.

### Profile

| Piece | File |
| --- | --- |
| `AppUser` refactored to mirror `users/{uid}` exactly | `features/auth/domain/models/app_user.dart` |
| `UserPreferences` for the private settings document | `features/auth/domain/models/user_preferences.dart` |
| `ProfileRepository` contract | `features/auth/domain/repositories/profile_repository.dart` |
| Firestore implementation (transactional, idempotent create) | `features/auth/data/repositories/firestore_profile_repository.dart` |
| Write controller (create-or-update) | `features/auth/presentation/providers/profile_controller.dart` |

### Routing, screens and shared UI

- `AuthRedirect.resolve` — a **pure** guard function
  (`app/router/auth_redirect.dart`), wired into `createAppRouter` through
  `appRouterProvider` with a `refreshListenable`, so the router reacts to auth
  changes. `KamApp` now uses that provider instead of building its own router.
- New routes: `/splash`, `/sign-in`, `/create-account` (plus the existing shell and
  `/profile`).
- Screens: `SplashScreen`, `SignInScreen`, `CreateAccountScreen`, `ProfileScreen`
  (rewritten), and a "Finish setting up your profile" card on the dashboard.
- New shared widget `core/ui/widgets/app_inline_message.dart`; new
  `PresentationMapping.fromAsyncNullableResult` so a *successful null* renders as
  **empty**, not loaded.
- `core/firebase/firebase_providers.dart` exposes the raw SDK handles, so the DI
  composition needs no Firebase import and the architecture test keeps its teeth.

### Firestore rules (strengthened, never relaxed)

`users/{uid}` and `users/{uid}/settings/preferences` now require server timestamps
(`== request.time`), keep `createdAt` immutable, validate `displayName` length on
both create and update, restrict the private document to known keys, constrain
`notificationPreference` to the four known values, and range-check home
coordinates (latitude ±90, longitude ±180).

---

## 2. Architecture

| Decision | Record |
| --- | --- |
| Identity and profile are separate concepts with separate types; a missing profile is a first-class `Success(null)` state | ADR-008 §1 |
| `AuthRepository` is identity-only; `ProfileRepository` owns `users/{uid}`; `AuthService` orchestrates registration | ADR-008 §2 |
| Registration reports three outcomes; a failed profile write keeps the session, deletes nothing, and is surfaced on two persistent screens | ADR-008 §3 |
| Operations apply their outcome immediately while the provider stream stays authoritative; a failed operation restores the previous state | ADR-008 §4 |
| An undeterminable session is `AuthError` (route to splash + retry), never a silent sign-out | ADR-008 §5 |
| The guard is a pure function; deny by default; no data route renders while the session is unknown | `AUTHENTICATION_ARCHITECTURE.md` §8 |

Phase 1–3 architecture was preserved. Four changes were made and are documented
(ADR-008 and `ARCHITECTURE.md` §17): identity-only `AuthRepository`, `AppUser`
narrowed to the stored schema, `Unauthenticated…` → `Unavailable…` repositories,
and `createAppRouter` gaining `refreshListenable`.

---

## 3. Tests

**222 Flutter tests pass** (was 114) and **47 Security Rules tests pass** (was 31).

| Suite | File | Focus |
| --- | --- | --- |
| Auth state | `test/unit/auth_state_test.dart` | six states, flags, no email in `toString` |
| Default composition | `test/unit/auth_composition_test.dart` | an unconfigured build reports accounts unavailable, saves nothing, invents no profile |
| Input rules | `test/unit/auth_input_validation_test.dart` | every field rule; client↔Rules parity; values never echoed |
| Orchestration | `test/unit/auth_service_test.dart` | three registration outcomes, partial failure, idempotent retry, sign-in, sign-out |
| State machine | `test/unit/auth_controller_test.dart` | restoration, sign-in/out, refusal while busy, revocation, outage, retry, cache invalidation, log hygiene |
| Guard | `test/unit/auth_redirect_test.dart` | every (state × location) cell incl. no-flicker cases |
| Presentation mapping | `test/unit/presentation_mapping_test.dart` | nullable result → empty |
| Sign-in screen | `test/widget/sign_in_screen_test.dart` | 9 cases: validation, vague credential message, in-flight, unavailable accounts, no internals |
| Create-account screen | `test/widget/create_account_screen_test.dart` | 11 cases incl. pending-profile reporting |
| Profile screen | `test/widget/profile_screen_test.dart` | 8 cases: loading, failure, missing profile, create, edit, validation, sign-out |
| Routing lifecycle | `test/widget/auth_routing_test.dart` | 10 cases: protection, first frame, full lifecycle, restart, revocation |
| Security Rules | `firebase/test/firestore.rules.test.js` | 16 new profile/preferences scenarios |

Notable tests: a pending profile never reports success and still lands in the app
with the incomplete banner; no test captures a password or an email address in the
log; and a *first frame* test proves protected content is not rendered before the
session is known.

---

## 4. Validation (actual commands and results)

| Command | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | ✅ `0 changed` |
| `flutter analyze` | ✅ `No issues found!` |
| `flutter test` | ✅ `All tests passed!` — **222 tests** |
| `firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"` | ✅ `# tests 47 / # pass 47 / # fail 0` |
| `flutter build apk --debug` | ✅ `Built build\app\outputs\flutter-apk\app-debug.apk` |
| `flutter build ios` | ⚠️ **Not executed** — macOS/Xcode required; the `ios` subcommand is unavailable on Windows |
| `firebase deploy --only firestore:rules` | ⚠️ **Not executed** — needs an authenticated account and a real project; none exists |
| End-to-end auth against the Auth emulator | ⚠️ **Not executed** — see §6.1 |

---

## 5. Deferred (intentionally, by phase)

| Item | Phase |
| --- | --- |
| FCM token registration at `users/{uid}/fcmTokens/{tokenId}` | Notifications (11) — the Phase 4 brief scopes to identity and profile, so registering a device token would have been unrelated work. The Rules and the collection already exist. |
| Password reset, email verification | Not required by the SRS in this phase; `emailVerified` is carried but no flow exists. |
| Account deletion | Privacy/data-lifecycle phase (13); the Rules already permit the owner to delete their own profile. |
| Profile image upload | Needs Cloud Storage. `photoUrl` is stored as a reference only. |
| Home-location picker and permissions | Location phase (7); the storage and validation already exist. |
| Pairing, device monitoring, rule engine, notifications, history | Phases 5–12, untouched. |

---

## 6. Known limitations

1. **No end-to-end run against the Firebase Auth emulator.** Driving `firebase_auth`
   from `flutter test` requires plugin platform channels, and no Android AVD or
   macOS host exists on this machine (`flutter emulators` reports none; FlutterFire
   does not support Windows desktop). Consequences: the *auth logic* (state machine,
   validation, orchestration, guard, screens) is verified with fakes, and the
   *Firestore* side is verified against the emulator with the real rules, but a real
   `createUserWithEmailAndPassword` → `users/{uid}` round trip has not been executed.
   What would close it: run the app on an Android emulator/device with the emulator
   suite (`--dart-define=FIREBASE_USE_EMULATORS=true`).
2. **No real Firebase project is connected**, so the app in this repository shows
   "Accounts are unavailable" and disables submit — which is the honest state, not a
   bug. Supplying the four `--dart-define` values enables the real flow.
3. **Cold-start deep link to a protected route is replaced** by splash → dashboard,
   because the guard cannot render protected content before the session is known. No
   deep links are configured yet; the fix is a return-path parameter
   (`?next=`) recorded in ADR-008.
4. **`createdAt` on `users/{uid}` must be written with a server timestamp.** A
   client that sends its own timestamp is rejected — deliberate, and the app complies.
5. **iOS build not validated** (Windows host).
6. **No App Check / rate limiting** — recorded in `FIREBASE_SECURITY.md` §9.

---

## 7. Risks

| Risk | Impact | Mitigation / status |
| --- | --- | --- |
| A registration whose profile write fails leaves an authenticated session without a profile | A user could exist with no profile | `RegistrationProfilePending` + a dashboard banner + the profile screen's "finish setup" form; `createProfile` is idempotent so recovery cannot duplicate; documented in ADR-008 §3 |
| Profile creation costs one transaction plus one read | Minor write/read amplification on registration only | Accepted and documented (`USER_PROFILE_MODEL.md` §5); the read is required because the server resolves the timestamp |
| The guard's decisions are security-relevant | A wrong redirect could expose a screen | The guard is pure and every (state × location) cell is unit-tested; the Rules remain the real authorization boundary |
| A second identifier could creep in alongside the uid | Ownership confusion | `AppUser.id` *is* the uid and no rule reads an id from request data; `request.auth.uid` is the only identity the Rules trust |
| `AuthError` routes everything to the splash | A provider outage blocks the app | It shows the cause and a retry; presenting a sign-in form that cannot work would be worse |
| Test fakes could diverge from the real repositories | False confidence | The fakes mirror the documented contract (emit identity on success, replay on subscribe, idempotent create) and are annotated as such; the Rules are tested against the real engine |

---

## 8. Security review (SRS Task 22)

| Check | Result |
| --- | --- |
| Passwords stored locally in plaintext | **No** — only disposed controllers, never persisted |
| Passwords stored in Firestore | **No** — no credential field; unknown keys rejected by the Rules |
| Auth tokens logged | **No** — contexts carry operation names and failure categories; a test greps every captured entry |
| Credentials/emails in logs | **No** — asserted by test |
| Secrets committed | **No** — no service account, Admin credential or project config in the repo |
| Ownership enforced | **Yes** — `isSelf(uid)` vs `request.auth.uid`, 16 emulator tests |
| Protected fields immutable | **Yes** — `createdAt` immutable, key allow-list, and `AppUser.copyWith`/`updateProfile` cannot express those fields |
| Routes protected | **Yes** — deny-by-default guard, tested at unit, widget and lifecycle level |
| Client-supplied ids trusted | **No** — no rule derives access from request data |
| Sensitive internals exposed | **No** — retained in `AppFailure.cause` for logs only |
| Account enumeration | Only `email-already-in-use` on registration; sign-in failures are merged into one message |

---

## 9. Next phase

**Phase 5 — Pairing, Consent and Connection Lifecycle** can start immediately:

1. The security foundation already exists: `pairs/{pairId}` with members, consents,
   sharing and lifecycle states, plus 31 pair/sharing rules tests to keep green.
2. What is still missing is the **server-side activation**: a Cloud Function must
   validate both consent documents in a transaction and set
   `pairs.status = 'active'`, because no client may do so (`FIREBASE_SECURITY.md`
   §5, §9.1–9.2). That is Phase 5's first task.
3. UI work plugs into the already-guarded `/pairing` route; `PairingCode` and
   `Consent` models are ready from Phase 1, and `SharingPreferences` already maps
   1:1 onto `pairs/{pairId}/sharing/{uid}`.
4. Nothing in Phases 1–4 needs re-architecting: identity, the guarded router and the
   profile document are all in place, and the pair subtree is already protected by
   tested rules.
