# ADR-008 — Identity is not the profile; and how a partial registration is reported

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 4

## Context

Phase 4 had to implement registration, sign-in, sign-out, session restoration and
the user profile on top of the Phase 3 Firebase foundation. Three problems had no
obvious answer:

1. **Registration spans two systems.** Firebase Authentication creates the
   account; Firestore stores the profile at `users/{uid}`. The uid only exists
   after the first call, so the second can fail on its own. The brief forbids
   reporting that as a successful registration, and forbids creating a duplicate
   profile when the operation is retried.
2. **Phase 1's `AuthRepository` conflated the two.** It exposed
   `watchCurrentUser() → AppUser?`, which forced a choice between inventing a
   profile whenever an identity existed, or pretending a signed-in user was signed
   out when the profile document was unreadable. Both contradict FR-048/NFR-006.
   Phase 1's `AppUser` also carried fields (`homeLocation`,
   `notificationPreference`) that Phase 3's Security Rules place in a *separate*
   private subdocument, so the Dart model no longer matched the stored schema.
3. **The router had to be auth-aware without flickering.** `AuthAuthenticating`
   and `AuthSigningOut` are real states, and a naive guard bounces the user
   between sign-in and the app while they are in flight.

## Decision

### 1. Identity and profile are separate concepts with separate types

| Concept | Type | Source | Can be absent? |
| --- | --- | --- | --- |
| Identity | `AuthIdentity` (`uid`, `email`, `emailVerified`) | Firebase Authentication | no, while signed in |
| Profile | `AppUser` (`id`, `displayName`, `photoUrl`, `timeZone`, timestamps) | `users/{uid}` | **yes** |
| Private settings | `UserPreferences` (`notificationPreference`, `homeLocation`) | `users/{uid}/settings/preferences` | yes (defaults) |

Consequences:

- `AppUser` now mirrors the `users/{uid}` document exactly. The fields that the
  Rules keep private moved to `UserPreferences`, so the model and the rules agree
  instead of the model being a convenient superset.
- The `null` profile is a first-class state: `currentUserProfileProvider` resolves
  to `Success(null)`, and `PresentationMapping.fromAsyncNullableResult` maps that
  to *empty*, not *loaded*. A missing profile can never be rendered as an invented
  user.
- The identity stream (`watchIdentity`) fires on its own, so **session restoration
  needs no startup code** — the first event from the provider *is* the restoration.

### 2. `AuthRepository` is identity-only; profile access is its own repository

`AuthRepository` exposes `watchIdentity`, `currentIdentity`, `registerWithEmail`,
`signInWithEmail`, `signOut` and an `isAvailable`/`unavailableReason` capability
pair. `ProfileRepository` owns `users/{uid}` and the private preferences document.
`AuthService` orchestrates the two for registration only, and is pure Dart so the
partial-failure path is unit-testable.

### 3. Registration reports three distinct outcomes

```dart
sealed class RegistrationResult
  RegistrationComplete(identity, profile)      // account + profile exist
  RegistrationRejected(failure)                // nothing was created; retry is safe
  RegistrationProfilePending(identity, failure) // account exists, profile does not
```

**Chosen partial-failure strategy — keep the session:**

- The account is **not** deleted. `delete()` needs a recent login, and discarding
  a valid credential because a second write failed would be destructive; the brief
  explicitly warns against blind deletion.
- The session is **not** torn down either. Signing out here would race the identity
  stream: Firebase emits the new identity immediately, so the guard moves the user
  into the app *before* `register()` returns — and then a sign-out would bounce
  them straight back out. That is visible flicker, which the brief names as a
  defect.
- Instead the user stays authenticated and the missing profile is surfaced on two
  persistent, non-transient surfaces: a "Finish setting up your profile" card on
  the dashboard, and the profile screen's explicit "not set up yet" state with a
  create form. Registration is therefore never silently reported as complete.
- `ProfileRepository.createProfile` is **idempotent** (a transaction returns the
  existing document untouched), so the recovery path and any retry cannot create a
  duplicate or overwrite an edit the user has since made.

### 4. Operations apply their own outcome; the stream stays authoritative

`AuthController` mirrors `watchIdentity()` *and* applies the result of
`signIn`/`register`/`signOut` immediately, so the UI never waits on stream timing.
The two agree on the same identity; the stream wins if they ever disagree. A
**failed** operation restores the previous state, so the app is never left
"authenticating" with nothing in flight, and a failed sign-out leaves the user
signed in rather than showing an empty authenticated shell.

### 5. An undeterminable session is its own state

`AuthError` exists so a provider outage is never presented as "signed out". The
guard routes *every* location to the splash screen in that state, which states the
problem and offers a retry instead of showing a sign-in form that cannot work.

## Consequences

Positive:

- The app can represent all six SRS-relevant states — initializing, unauthenticated,
  authenticating, authenticated, signing out, error — and each one has a defined
  route and screen.
- A missing profile is a normal, recoverable state rather than a crash or a
  fabrication, which is exactly the "no invented device state" principle applied to
  user data.
- Registration cannot silently half-succeed, and cannot duplicate a profile.
- `AuthService`, `AuthController`, `AuthRedirect` and `ProfileController` are all
  testable without Firebase, so 217 Flutter tests run with no project and no
  platform channel; the Security Rules are proven separately against the emulator.

Negative / accepted trade-offs:

- A cold-start deep link to a protected route is replaced by the splash screen and
  then the dashboard, because the guard cannot show protected content before the
  session is known. The app has no deep-link configuration today, so no real flow
  is affected; a return-path (`?next=`) mechanism is the documented fix when push
  notifications start opening routes.
- A pending profile leaves an authenticated session whose profile is missing. That
  is deliberate (it is the recovery path), but it does mean "authenticated" alone
  does not imply "fully provisioned" anywhere in the app.
- `users/{uid}` now requires `createdAt`/`updatedAt` to equal `request.time`, so a
  client cannot write a profile with its own timestamps. This is a *strengthening*
  of the Phase 3 rules; the app's write shapes were updated to comply rather than
  the rules being relaxed.

## Alternatives considered

- **Report pending registration as a plain failure and sign the user out.**
  Rejected: it races the identity stream and produces a visible bounce (see §3).
- **Delete the Firebase account when the profile write fails.** Rejected: needs a
  recent login, destroys a valid credential, and the brief warns against it.
- **Store `homeLocation`/`notificationPreference` on `users/{uid}`.** Rejected:
  the Phase 3 rules keep them owner-only in a subdocument, and merging them would
  either weaken those rules or make an unenforceable field.
- **Model a missing profile by constructing a default `AppUser`.** Rejected: it is
  exactly the fabrication the SRS forbids (FR-048, NFR-006).
- **Let screens call `FirebaseAuth`/`FirebaseFirestore` directly.** Rejected by
  the architecture test and the brief (constraint 4).
- **A return-path (`?next=`) deep-link mechanism now.** Rejected as speculative:
  no deep links are configured yet, and constraint 8 forbids inventing
  requirements. Recorded as the documented follow-up.
