# Firebase Architecture

How Firebase is wired into the app, what each service is responsible for, and how
development, emulator and production environments are separated.

Related: `FIRESTORE_DATA_MODEL.md`, `FIREBASE_SECURITY.md`,
`ADR-002-firebase-boundaries.md`, `ADR-007-firebase-integration.md`.

> **Status note (important).** This phase establishes and verifies the Firebase
> *foundation*: SDK integration, configuration strategy, emulator workflow, data
> model, security rules and rules tests. **No real Firebase project exists yet**,
> because no project or credentials are available in this environment. Nothing
> here claims a successful deployment. `docs/PHASE_03_COMPLETION_REPORT.md` §5
> lists the exact manual steps an operator must perform.

---

## 1. Service responsibilities

| Service | Responsibility | Phase 3 status |
| --- | --- | --- |
| **Firebase Authentication** | Identity: sign-in, sign-out, session, `uid` | Email/password flows and session restoration implemented; no live project configured |
| **Cloud Firestore** | Persistent, synchronized application data: profiles, pairs, consent, sharing, device state, location, rules, interpretations, events, notifications | SDK added; collection model, ownership and rules **designed, implemented and tested**; live repositories are added with their feature phases |
| **Firebase Cloud Messaging** | Potential remote push delivery | Not used. The unused SDK dependency was removed; token registration and remote sending are deferred |
| **Cloud Functions** | Trusted server-side operations the client must not perform | **Excluded** — Spark-only decision in §7; no source, emulator or deploy target |
| **Cloud Storage** | (Not used.) No binary/media requirement exists in the SRS | Not added |
| **Remote Config / Analytics / Crashlytics** | Not required by the SRS | Not added |

The SRS rule that shapes everything: **authorization is enforced server-side
(Security Rules); observation happens client-side.** Only the device can measure
its own battery; only the backend may decide who is allowed to read it.

### The client never contains a privileged credential

`google-services.json`/`GoogleService-Info.plist` and `firebase_options.dart`
contain only client-safe identifiers. Admin SDK service accounts are server-only
and are never bundled or committed (see `FIREBASE_SECURITY.md` §7).

---

## 2. Flutter integration

```
AppBootstrap.initialize()
  → AppConfig.fromEnvironment()          --dart-define values
  → FirebaseBootstrap.initialize(config, logger: logger)
       ├─ not configured  → log, return false, app continues offline
       ├─ partial config  → warn loudly, return false (fail closed)
       └─ configured      → Firebase.initializeApp(options: FirebaseConfig.optionsFor(config))
                            → FirebaseEmulators.connect(...) if requested
                            → true
```

Design points:

- **One initialization site.** Firebase is initialized from `AppBootstrap` only;
  no widget or feature calls `Firebase.initializeApp`.
- **Failures degrade, never block.** `FirebaseBootstrap.initialize` classifies any
  error into an `AppFailure` (via `FirebaseErrorMapper`), logs it without secrets,
  and returns `false`. It never throws to the caller, so a backend outage cannot
  prevent the app from starting (NFR-014, NFR-015).
- **Explicit `FirebaseOptions` instead of `google-services.json`.** Options are
  assembled from client-safe `--dart-define` values, which is a
  FlutterFire-supported approach and means the build does not require the
  `com.google.gms.google-services` Gradle plugin. See `ADR-007`.
- **Testable without Firebase.** Unit tests assert the not-configured and
  partial-configuration paths (`test/unit/app_startup_test.dart`,
  `test/unit/firebase_config_test.dart`) without needing a project.
- **Boundary enforced by a test.** `test/architecture/domain_purity_test.dart`
  fails the build if a Firebase SDK is imported anywhere except
  `lib/core/firebase/` and `lib/features/*/data/`.

---

## 3. Environment strategy

Three environments, each mapped to its **own Firebase project** so a development
build can never write to production data:

| Environment | Firebase project | Selected by | Data |
| --- | --- | --- | --- |
| Local development | `demo-kam` (Firebase Emulator Suite, `demo-` prefixed so it needs no account) | `--dart-define=FIREBASE_USE_EMULATORS=true` | ephemeral, in-memory, wiped on stop |
| Development (shared) | `know-about-me-dev` **(to be created)** | `APP_ENV=development` + that project's identifiers | disposable |
| Production | `know-about-me` **(to be created)** | `APP_ENV=production` + that project's identifiers | real user data |

Guardrails:

- `AppConfig.hasFirebaseConfiguration` requires *all* identifiers. A partial set is
  treated as **not configured** and logged as a warning, so a half-edited build
  fails closed instead of silently initializing against the wrong project.
- `AppConfig.hasMisconfiguredEmulatorRequest` flags "emulators requested but no
  project configured".
- `FirebaseEmulators.connect` is the **only** place emulator endpoints are set, so
  a release build cannot accidentally point at a laptop (SRS constraint 6).
- **Cloud Messaging is not emulatable.** The Emulator Suite has no FCM emulator.
  No messaging client SDK or push delivery is currently wired into the app.
- The project ids for development and production are **not invented here**; they
  are placeholders in this table only and must be supplied by an operator with
  access to the Firebase console (§5).

### Providing configuration

```bash
# Local, against the Emulator Suite
flutter run \
  --dart-define=FIREBASE_PROJECT_ID=demo-kam \
  --dart-define=FIREBASE_API_KEY=demo-api-key \
  --dart-define=FIREBASE_APP_ID=1:000000000000:android:0000000000000000000000 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=000000000000 \
  --dart-define=FIREBASE_USE_EMULATORS=true

# A real environment (values come from the Firebase console)
flutter run \
  --dart-define=APP_ENV=production \
  --dart-define=FIREBASE_PROJECT_ID=<project-id> \
  --dart-define=FIREBASE_API_KEY=<web/android/ios api key> \
  --dart-define=FIREBASE_APP_ID=<app id> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender id>
```

For multi-value setups, prefer `--dart-define-from-file=firebase.dev.json`; the
file stays out of version control (`.gitignore` blocks `*.env*`, and a
`firebase.*.json` containing only client-safe identifiers may be committed
deliberately if the team chooses).

---

## 4. Firebase CLI configuration

| File | Purpose |
| --- | --- |
| `firebase.json` | Declares Firestore rules/indexes paths and emulator ports |
| `.firebaserc` | Project aliases; `default` is the local `demo-kam` emulator project |
| `firebase/firestore.rules` | Security rules |
| `firebase/firestore.indexes.json` | Composite indexes |
| `firebase/package.json` | Node project for the rules tests |
| `firebase/test/firestore.rules.test.js` | Emulator rules tests |

```bash
cd kam
firebase --version                        # 15.24.0 verified in this environment
firebase emulators:start --only firestore,auth
firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"
firebase emulators:exec --only firestore "npm --prefix firebase test"
```

Deployment commands (require a real, authenticated project — **not run here**):

```bash
firebase use development                  # or: firebase use production
firebase deploy --only firestore:rules    # rules only
firebase deploy --only firestore:indexes  # indexes only
```

`firebase/README.md` repeats these commands with the setup steps for a new
operator.

---

## 5. Required manual setup (not performed in this environment)

Because no Firebase account/project is available, these steps are **outstanding**:

1. Create the Firebase projects (`*-dev`, production) in the Firebase console.
2. Enable **Authentication** (Email/Password and/or the chosen providers).
3. Create a **Cloud Firestore** database in each project (production mode).
4. Register the Android and iOS apps; record `projectId`, `apiKey`, `appId` and
   `messagingSenderId`.
5. `firebase login` and `firebase use <project>` locally (requires a human
   account; **not** scriptable here).
6. `firebase deploy --only firestore:rules,firestore:indexes` per project.
7. Optionally `flutterfire configure` to generate `firebase_options.dart` — not
   used by this codebase, which reads `--dart-define` values instead (ADR-007).
8. Enable **App Check** before shipping (see `FIREBASE_SECURITY.md` §9).

Until step 1–4 are done, the app runs offline: every device metric renders as an
explicit `Unknown`/`Unsupported` state rather than a fabricated value.

---

## 6. FCM boundary (reserved; not implemented)

The notification feature is not implemented, and `firebase_messaging` is not a
project dependency. These fields/rules reserve a safe owner-only location if a
later notification phase adds token registration.

| Concern | Decision |
| --- | --- |
| Token storage | `users/{userId}/fcmTokens/{tokenId}`, **owner-only**, never readable by a partner |
| Why owner-only | a token is a capability to push to someone's device; a partner must never obtain it |
| Token lifecycle | Deferred. No SDK or token writer currently exists |
| Device association | each token document records `platform`, `deviceId`, `createdAt`, `lastSeenAt`; the id is a hash of the token so the raw token is not used as a path segment |
| Revocation | Define token deletion together with any future registration flow |
| Authorization | No FCM package, token registration or notification permission prompt is currently implemented |
| Server-side sending | **None exists.** Sending needs a trusted sender with an FCM credential, and the Spark-only architecture has no server — so remote push is **deferred** rather than given a credential. Local platform notification delivery is also not implemented yet. **The FCM server key/credential is never in the client.** |
| Data boundary | FCM carries *notification* payloads only; it is never the source of truth for application state (SRS: do not treat FCM as state) |

---

## 7. Cloud Functions boundary — none, permanently

**There is no Cloud Functions project, and there will not be one.** The project
must run on the Firebase **Spark** plan without a Cloud Billing account, and Cloud
Functions are only deployable on Blaze — the billing account is the blocker, not
the cost. The same applies to Cloud Run, Cloud Scheduler, Pub/Sub and any
Extension that bundles Functions.

This section replaces an earlier position that deferred four capabilities to a
future Functions project. That plan is superseded by
[ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md); the full
operation-by-operation audit and its replacements are in
[SPARK_ONLY_ARCHITECTURE.md](SPARK_ONLY_ARCHITECTURE.md) §2.

In summary, each former server responsibility is now enforced by Security Rules
verifying facts the client cannot forge:

| Formerly a server operation | Now |
| --- | --- |
| Activate a pair | `bothConsentsGranted()` — the rules read **both** consent documents; each can only be written by its own subject |
| Issue/validate a pairing code | Client CSPRNG + rules enforcing ≥20 chars, ≤1 h expiry, single-use redemption, and **`list` denied** |
| Dispatch a notification | **Local** notification from the user's own device; the owner writes their own per-user record. Remote push is deferred |
| Evaluate rules | **Client** (`RuleEvaluator`) — pure and deterministic; inputs are facts the user may already read |
| Scheduled retention/deletion | **Deferred** — needs a cross-user scheduler, so it is documented rather than delegated |

The vital property is unchanged: **the client is never the authority.** A client
may *request* activation; it cannot assert the other member's consent, write into
anyone else's collection, or redeem a code twice.

Two consequences worth stating plainly:

1. **Remote push to a partner's device does not exist.** No sending path, no
   server credential. Local alert delivery is also not implemented; the
   notification boundary reports unsupported. The UI must show last-known state
   with its age when updates are unavailable.
2. **Cross-user retention/cleanup is unenforced.** Ownership-scoped lazy cleanup
   only. Granting a client cross-user delete is exactly the compromise this
   architecture exists to prevent.

No Functions emulator is configured: this Spark-only project has no Functions
source, emulator port, or deploy target.

---

## 8. Error handling (SRS Task 22)

`FirebaseErrorMapper` (in `lib/core/firebase/`) converts SDK errors into the
application's classified `AppFailure` vocabulary:

| Firebase condition | Resulting failure | User-facing message |
| --- | --- | --- |
| `permission-denied` | `PermissionFailure` | "You do not have access to this information." |
| `unauthenticated` | `AuthenticationFailure` | "Your session has expired. Please sign in again." |
| `not-found` | `NotFoundFailure` | "That information is no longer available." |
| `unavailable`, `network-request-failed` | `RemoteServiceFailure` | "Could not reach the service…" |
| `deadline-exceeded` | `RemoteServiceFailure` | "The request took too long…" |
| `resource-exhausted` | `RemoteServiceFailure` | "The service is busy right now…" |
| `failed-precondition`, `invalid-argument` | `ValidationFailure` | "That action is not allowed in the current state." |
| Auth credential errors (`user-not-found`, `wrong-password`, `invalid-credential`) | `AuthenticationFailure` | one identical, vague message (no account enumeration) |
| `email-already-in-use`, `weak-password`, `invalid-email` | `ValidationFailure` | specific, actionable message |
| `too-many-requests` | `RemoteServiceFailure` | "Too many attempts. Please wait and try again." |
| anything unrecognised | `RemoteServiceFailure` / `UnexpectedFailure` | generic message |

Raw SDK text is never shown to a user; it is retained in `AppFailure.cause` for
logging only. This is covered by `test/unit/firebase_error_mapper_test.dart`.

---

## 9. Offline strategy (SRS Task 23)

Detailed behaviour and its data-model consequences are in
`FIRESTORE_DATA_MODEL.md` §9. The application-level contract:

- Firestore's local cache makes reads work offline and queues writes.
- **Cached is not current.** Every remote value carries `observedAt`, and the UI
  classifies freshness and shows the age (`FreshnessIndicator`), so
  `current / stale / offline / unknown` are visually distinguishable
  (FR-061, NFR-025).
- An offline device cannot be assumed powered off; only reachability and
  last-seen time are ever reported (FR-015, FR-070).
- Reconnection flushes pending writes and re-establishes listeners, after which
  freshness improves on its own (FR-060, FR-072).

---

## 10. Cost considerations (SRS Task 24)

Documented in `FIRESTORE_DATA_MODEL.md` §10. The design rules that matter most:

- current state is **one document**, overwritten in place;
- only **meaningful transitions** become events;
- rules `get()` at most **two** documents per partner read;
- listeners are bounded to the handful of documents the dashboard renders;
- no index exists for a query the product does not have.

---

## 11. Known limitations

1. **No real Firebase project is configured**, so no deployment was performed and
   the app currently starts offline (`PHASE_03_COMPLETION_REPORT.md` §5).
2. **Authentication flows are not implemented** (intentionally).
3. **Pair activation needs both consent documents, not a backend.** The rules
   gate the transition, so the flow is still fail-closed without mutual consent
   (§7).
4. **No Cloud Functions project, and none is planned** (§7).
5. **No FCM sending path**, no notification permission prompt, and no remote push
   of any kind.
6. **iOS is unvalidated** on this Windows host; FlutterFire's iOS setup
   (CocoaPods, `minimumOsVersion`) must be verified on macOS. `firebase_core` and
   friends require iOS 13+, which the current template satisfies, but this is an
   assumption, not a verified result.
7. **Emulator ports are fixed** (8080/9099/5001/4000); a machine with those ports
   busy must change `firebase.json` and `FirebaseEmulatorPorts` together.
