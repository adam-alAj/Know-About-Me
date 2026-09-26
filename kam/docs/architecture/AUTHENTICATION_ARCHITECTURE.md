# Authentication architecture

How identity works in this application, **as implemented** after Phase 4.

Related documents:

- `USER_PROFILE_MODEL.md` — the `users/{uid}` document and its private settings.
- `FIREBASE_ARCHITECTURE.md` §2, §4 — FlutterFire integration and configuration.
- `FIREBASE_SECURITY.md` — authorization, including the profile rules.
- `../decisions/ADR-008-identity-profile-separation.md` — why identity and profile
  are separate, and the registration failure strategy.

Scope of this phase: Firebase Authentication with **email + password**, session
restoration, sign-out, the router guard, and the user profile. Password reset,
email verification, account deletion and FCM token registration are **not**
implemented (see §12).

---

## 1. Where the code lives

```
lib/features/auth/
├── domain/
│   ├── models/
│   │   ├── auth_identity.dart     who the provider says you are (uid, email, verified)
│   │   ├── auth_state.dart        sealed: initializing | unauthenticated | authenticating
│   │   │                                  | authenticated | signingOut | error
│   │   ├── app_user.dart          the users/{uid} document
│   │   └── user_preferences.dart  the private settings document
│   ├── repositories/
│   │   ├── auth_repository.dart   identity contract (isAvailable, watch, register, signIn, signOut)
│   │   └── profile_repository.dart profile contract (get, watch, create, update, preferences)
│   ├── services/auth_service.dart registration/sign-in/sign-out orchestration
│   └── validation/auth_input_validation.dart  pure-Dart input rules
├── data/repositories/
│   ├── firebase_auth_repository.dart     the only FirebaseAuth user
│   ├── firestore_profile_repository.dart the only users/{uid} writer
│   ├── unavailable_auth_repository.dart  honest no-op for an unconfigured build
│   └── unavailable_profile_repository.dart
└── presentation/
    ├── splash_screen.dart  sign_in_screen.dart  create_account_screen.dart
    ├── profile_screen.dart
    └── providers/ auth_providers.dart  auth_controller.dart  profile_controller.dart
```

Screens never import a Firebase package: the architecture test
(`test/architecture/domain_purity_test.dart`) fails the build if an SDK import
appears outside `lib/core/firebase/` and `lib/features/*/data/` (ADR-007).

---

## 2. Identity and profile are different things

| | Identity | Profile |
| --- | --- | --- |
| Type | `AuthIdentity` | `AppUser` |
| Source | Firebase Authentication | `users/{uid}` in Firestore |
| Always present while signed in? | yes | **no** |
| Route/screen | guard decides | profile screen, dashboard banner |

The distinction is what makes the honest states possible:

```text
sampled state                     how the app represents it
────────────────────────────────  ─────────────────────────────────────────────
signed out                        AuthUnauthenticated → /sign-in
signed in, profile loading        profile provider AsyncLoading → spinner
signed in, profile present        profile provider Success(AppUser) → editor
signed in, profile missing        profile provider Success(null) → "not set up yet"
signed in, profile unreadable     profile provider Failure(message) → error + retry
provider unreachable              AuthError → /splash with a retry
```

`Success(null)` is a real state, never a fabricated `AppUser`
(FR-048, NFR-006). Full detail: ADR-008 and `USER_PROFILE_MODEL.md`.

---

## 3. State machine

`AuthState` is `sealed`, so every consumer must handle all six cases:

| State | `isAuthenticated` | `isBusy` | Reachable routes |
| --- | --- | --- | --- |
| `AuthInitializing` | no | no | splash; non-data routes pass through |
| `AuthUnauthenticated` | no | no | sign-in, create-account |
| `AuthAuthenticating(previous)` | if `previous != null` | yes | as previous, or the auth flow |
| `AuthAuthenticated(identity)` | yes | no | the application |
| `AuthSigningOut(identity)` | yes | yes | where the user already is (no bounce) |
| `AuthError(failure)` | no | no | splash only (states the problem, offers retry) |

Transitions:

```text
                     ┌──────────────── watchIdentity() emits null ───────────────┐
                     │                                                           ▼
  build() ──► AuthInitializing ──identity ──► AuthAuthenticated ──signOut()─► AuthSigningOut
                     │                              ▲                              │
        stream error │                              │ identity                     │ provider confirms
                     ▼                              │                              ▼
                 AuthError ──retry()──► AuthInitializing   signIn()/register() ──► AuthUnauthenticated
```

Rules the implementation guarantees:

- `AuthController.build()` returns `AuthInitializing` and then mirrors the
  identity stream, so **session restoration is the stream's first event** — there
  is no separate startup code path (SRS Task 8).
- A failed `signIn`/`register` restores the previous state and returns the
  classified failure, so the app is never stuck "busy".
- A failed `signOut` restores `AuthAuthenticated`: the provider still holds the
  session, so the app must not pretend otherwise.
- `signOut()` invalidates the profile and preferences families, so no
  authenticated data survives the sign-out (SRS Task 7, Task 22).
- A stream error produces `AuthError`, never a silent sign-out (SRS Task 21).

---

## 4. Repository contracts

```dart
abstract interface class AuthRepository {
  bool get isAvailable;             // false = no account service in this build
  String? get unavailableReason;    // user-safe explanation, null when available
  Stream<AuthIdentity?> watchIdentity();
  Future<Result<AuthIdentity?>> currentIdentity();
  Future<Result<AuthIdentity>> registerWithEmail({required String email, required String password});
  Future<Result<AuthIdentity>> signInWithEmail({required String email, required String password});
  Future<Result<void>> signOut();
}
```

`ProfileRepository` is documented in `USER_PROFILE_MODEL.md` §5.

Composition (`authRepositoryProvider`):

```dart
if (!firebaseAvailableProvider) return const UnavailableAuthRepository();
return FirebaseAuthRepository(firebaseAuthProvider, loggerProvider);
```

So a build with no Firebase configuration runs with
`isAvailable == false`: the sign-in screen states that accounts are unavailable
and disables submit, rather than offering a form that cannot succeed
(SRS constraint 10). "Nobody is signed in" is still reported truthfully as `null`.

### Firebase Auth usage

- Email + password only. The SRS does not require another provider, and adding one
  would be an invented requirement.
- `_guarded()` wraps every SDK call: any throw becomes a classified `AppFailure`
  through `FirebaseErrorMapper`. (`Result.guard` is *not* used here, because its
  generic fallback would not understand Firebase error codes.)
- `watchIdentity()` is implemented with `async*` so a stream failure is converted
  into a classified failure and emitted as an error — signalling "unknown", not
  "signed out".

---

## 5. Registration flow (SRS Task 4, Task 5)

```text
CreateAccountScreen
   │  validate locally (AuthInputValidation)
   ▼
AuthController.register()  →  AuthService.register()
   │  1. validation failure        → RegistrationRejected(failure)      [nothing created]
   │  2. auth.registerWithEmail()  → failure → RegistrationRejected      [nothing created]
   │  3. profiles.createProfile(uid, displayName)   (idempotent)
   │        success → RegistrationComplete(identity, profile)
   │        failure → RegistrationProfilePending(identity, failure)
   ▼
AuthController applies the identity → guard moves the user into the app
```

Partial failure (step 3) is **not** reported as success:
`RegistrationProfilePending` keeps the session, tells the user their account was
created, and leaves the missing profile to the two surfaces that can fix it — the
dashboard's "Finish setting up your profile" card and the profile screen's
"not set up yet" form. `createProfile` returns an existing document untouched, so
the recovery path and any retry cannot duplicate or overwrite a profile.
The reasoning, including why the session is not torn down, is in ADR-008 §3.

---

## 6. Sign-in, sign-out and session lifecycle

- **Sign-in**: validate locally, `signInWithEmail`, then apply the identity. The
  profile loads independently through `currentUserProfileProvider`, so a missing
  profile never blocks authentication (SRS Task 6, Task 14).
- **Sign-out**: set `AuthSigningOut` (so the UI does not blank), call
  `signOut()`, then `AuthUnauthenticated` and invalidate cached profile data. The
  account and the profile document are untouched — logout is not account deletion
  (SRS Task 7).
- **Restoration**: on a warm start the provider re-emits the stored session, so an
  authenticated user is not forced through sign-in again (SRS Task 8, Task 24).
- **External change**: a session revoked elsewhere arrives on the stream and moves
  the user to the sign-in screen with no user action.

---

## 7. Validation and error mapping

`AuthInputValidation` (pure Dart) is used directly as `TextFormField.validator`, so
the form and the unit tests share one implementation:

| Field | Rule | Also enforced by |
| --- | --- | --- |
| Email | non-empty, `local@domain.tld` | Firebase Authentication |
| Password | ≥ 8 characters | Firebase Authentication (≥ 6) |
| Confirm password | equals password | — (client only) |
| Display name | non-empty, ≤ 120 characters, trimmed | `firestore.rules` (`size() <= 120`) |

The 8-character floor is a product choice (NFR-001); Firebase's own minimum is 6.
Messages never echo the rejected value, so a credential cannot leak into a log or
a UI string.

`FirebaseErrorMapper` (Phase 3) already classifies the auth codes. Phase 4 relies
on it unchanged, including its deliberate vagueness:

| Firebase code | Shown to the user |
| --- | --- |
| `user-not-found`, `wrong-password`, `invalid-credential` | "The email or password is incorrect." |
| `email-already-in-use` | "That email address is already registered." |
| `weak-password` | "Please choose a stronger password." |
| `invalid-email` | "Please enter a valid email address." |
| `too-many-requests` | "Too many attempts. Please wait and try again." |
| `network-request-failed`, `unavailable` | "Could not reach the service. Check your connection and try again." |
| `user-disabled` | "This account is not available. Please contact support." |
| `operation-not-allowed` | "That sign-in method is not enabled." |
| anything unmapped | a generic, non-specific message |

Sign-in failures for the three credential codes are merged on purpose: separating
them would let an attacker enumerate accounts (SRS constraint 10). `cause` keeps
the SDK detail for logs only.

---

## 8. Routing and the guard

`AuthRedirect.resolve(authState, location)` is a **pure function**; the router only
calls it, so every case is a plain unit test (`test/unit/auth_redirect_test.dart`).

| Authentication state | Data route (dashboard, rules, history, privacy, profile) | Auth route (sign-in, create-account) | Splash | Unknown path |
| --- | --- | --- | --- | --- |
| initializing | splash | allow | allow | allow |
| error | splash | splash | allow | splash |
| unauthenticated | sign-in | allow | sign-in | sign-in |
| authenticating (was signed out) | sign-in | allow | sign-in | sign-in |
| authenticating (was signed in) | allow | dashboard | dashboard | allow |
| authenticated | allow | dashboard | dashboard | allow |
| signing out | allow | allow | allow | allow |

Design notes:

- **Deny by default.** Only `sign-in` and `create-account` are reachable without a
  session, so protection does not depend on hiding navigation controls.
- **No protected content before the session is known.** Data routes go to the
  splash while initializing.
- **No flicker.** `AuthSigningOut` keeps the user where they are; the guard only
  moves them once the provider confirms, which is a single transition. A
  re-authentication (`AuthAuthenticating` with a previous identity) also stays put.
- **Unknown paths are not rewritten while initializing**, so the not-found screen
  still works on a cold start.
- `refreshListenable` is a `ChangeNotifier` fed by `ref.listen(authStateProvider)`,
  so the redirect re-runs the moment the state changes.

---

## 9. Screens

| Screen | State it must handle |
| --- | --- |
| `SplashScreen` | initializing (spinner with a semantic label); error (message + retry) |
| `SignInScreen` | validation errors, in-flight (spinner, disabled fields), classified failure, accounts unavailable (warning + disabled submit) |
| `CreateAccountScreen` | as sign-in, plus the "account created, profile pending" warning |
| `ProfileScreen` | loading, failure + retry, **missing profile** (create form), present (edit form), notification preference, sign-out |

Form state (field contents, submit-in-flight, last message) is ephemeral UI state
and lives in the widget, per ADR-006. Application state (who is signed in, the
profile, preferences) lives in providers. Both screens use the shared
`AppScaffold`, `AppCard`, `AppButton`, `AppInlineMessage`, `DataStateView`,
`LoadingView` and `ErrorView`, so loading/error/empty states are rendered once,
consistently (SRS Task 18).

Errors are returned from the controller rather than shown as snack bars, so the
message stays on screen while the user corrects the input.

---

## 10. Security review (SRS Task 22)

| Check | Result |
| --- | --- |
| Passwords stored locally in plaintext | **No.** Only `TextEditingController`s, disposed on screen close, never persisted. |
| Passwords stored in Firestore | **No.** `users/{uid}` has no credential field and the rules reject unknown keys. |
| Auth tokens logged | **No.** Log context carries operation names and failure types only; `developer_logger`'s `sanitizeContext` redacts sensitive keys as defence in depth. |
| Credentials or emails in logs | **No** — asserted by a test that greps all captured log entries. |
| Secrets committed | **No.** No service-account file, Admin credential or project config is in the repository. |
| Profile ownership enforced | **Yes** by `firestore.rules` (`isSelf` against `request.auth.uid`), verified by 16 emulator tests. |
| Protected routes protected | **Yes** by `AuthRedirect`, verified by unit, widget and lifecycle tests. |
| Client cannot change ownership/createdAt | **Yes** — the rules require `createdAt == resource.data.createdAt` and `hasOnly([...])`, and `ProfileRepository.updateProfile` cannot even express those fields. |
| `request.auth.uid` used, not a client-supplied id | **Yes** — no rule reads an id from request data to decide access; the path must equal the token's uid. |
| Sensitive internals shown to users | **No** — internals stay in `AppFailure.cause`, for logs only. |
| Account enumeration | Only where the flow requires it (`email-already-in-use` on registration). Sign-in failures are merged. |

---

## 11. Testing strategy

| Layer | File(s) | What it proves |
| --- | --- | --- |
| State model | `test/unit/auth_state_test.dart` | all six states, busy/authenticated/unavailable flags |
| Default composition | `test/unit/auth_composition_test.dart` | the real providers with no Firebase: accounts unavailable, writes fail, no fabricated profile |
| Input rules | `test/unit/auth_input_validation_test.dart` | every field rule, client↔rules parity, no echoing |
| Orchestration | `test/unit/auth_service_test.dart` | registration outcomes incl. partial failure and idempotent retry |
| State machine | `test/unit/auth_controller_test.dart` | transitions, restoration, external revocation, outage, retry, sign-out, log hygiene |
| Guard | `test/unit/auth_redirect_test.dart` | every (state × location) cell of §8 |
| Async → presentation | `test/unit/presentation_mapping_test.dart` | nullable results map to *empty*, not *loaded* |
| Screens | `test/widget/sign_in_screen_test.dart`, `create_account_screen_test.dart`, `profile_screen_test.dart` | validation, in-flight, failures, missing profile, editing, sign-out |
| Routing lifecycle | `test/widget/auth_routing_test.dart` | signed out/in, protection, first frame, full lifecycle, restart |
| Architecture | `test/architecture/domain_purity_test.dart` | Firebase stays out of domain and presentation |
| Security Rules | `firebase/test/firestore.rules.test.js` | 47 scenarios, 16 of them profile/preferences |

Tests use `FakeAuthRepository` / `FakeProfileRepository`, so nothing touches
Firebase, the network or a platform channel. Firebase-specific code is either a
pure function (config assembly, error mapping, validation) or proven against the
emulator.

---

## 12. Known limitations and deferred work

| Item | Status |
| --- | --- |
| Real end-to-end check against the Auth emulator | **Not executed.** Driving `firebase_auth` from a Dart test needs plugin platform channels; no Android AVD is available on this machine. The auth *logic* is verified with fakes, and the Firestore side is verified against the emulator. |
| Cold-start deep link to a protected route | Replaced by splash → dashboard. No deep links are configured yet; the fix is a return-path (`?next=`) parameter, recorded in ADR-008. |
| Password reset | Not implemented — not required by the SRS in this phase. |
| Email verification | `emailVerified` is carried on `AuthIdentity` but no verification flow exists. |
| Account deletion | Not implemented; the rules already allow the owner to delete their own profile (NFR-032), and retention policy belongs to a later phase. |
| FCM token registration | Moved to the notifications phase: the Phase 4 brief scopes to identity and profile, so registering a device token here would have been unrelated work. `users/{uid}/fcmTokens/{tokenId}` and its rules already exist. |
| Human-readable failure codes for support | Not implemented; failures are logged with a category only. Deferred to the observability work. |
| Rate limiting / App Check | Still absent (recorded in `FIREBASE_SECURITY.md` §9). |
