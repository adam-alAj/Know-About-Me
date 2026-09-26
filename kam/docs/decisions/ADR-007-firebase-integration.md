# ADR-007 — Firebase integration approach, configuration and boundaries

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 3

## Context

ADR-002 decided to defer Firebase until a foundation existed, and to keep no
Firebase dependency in the client at that time. Phase 3 is where Firebase is
introduced. Three problems had to be solved honestly:

1. **No Firebase project or credentials are available in this environment.** The
   documented setup path (`flutterfire configure`) generates
   `firebase_options.dart` from a real project, and the Android build normally
   requires `google-services.json` plus the `com.google.gms.google-services`
   Gradle plugin. Fabricating a project or a config file is explicitly forbidden
   (constraint 10: no fabricated Firebase resources).
2. **Authorization must not drift into the client.** ADR-002 fixed the split;
   Phase 3 had to make it real and testable.
3. **Local development must not be able to write to production data**
   (constraint 6).

## Decision

### 1. Configure Firebase with explicit `FirebaseOptions` from `--dart-define`

`FirebaseConfig.optionsFor(AppConfig)` assembles `FirebaseOptions` from
client-safe compile-time values (`FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`,
`FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, optional auth domain / storage
bucket). This is a FlutterFire-supported alternative to bundling
`google-services.json`, and it means:

- the Android build works **without** the Google Services Gradle plugin,
- the same binary is re-targeted by changing `--dart-define` values,
- no project-specific JSON needs to be committed or faked.

`AppConfig.hasFirebaseConfiguration` requires **all four** identifiers. A partial
set is treated as not configured and logged as a warning, so a half-edited build
fails closed rather than initializing against the wrong project.

### 2. Firebase initialization is one guarded call in bootstrap

`FirebaseBootstrap.initialize(config, logger:)` is called only from
`AppBootstrap`. It returns `false` (and never throws) when Firebase is not
configured or when initialization fails, classifying any error through
`FirebaseErrorMapper` first. The app then continues offline with explicit
non-available states.

### 3. The Emulator Suite is the default local backend

`firebase.json` declares Auth/Firestore/Functions/UI ports and
`singleProjectMode`; `.firebaserc` defaults to `demo-kam`. The `demo-` prefix is
Firebase's documented convention for a local-only project that needs no account
and cannot reach production. `FirebaseEmulators.connect` is the single place
emulator endpoints are set, gated on `FIREBASE_USE_EMULATORS`.

### 4. Firebase is confined to two boundaries, and a test enforces it

| Allowed | Not allowed |
| --- | --- |
| `lib/core/firebase/` (initialization, options, emulator wiring, error mapping) | `lib/features/*/domain/` |
| `lib/features/*/data/` (repositories, data sources) | `lib/features/*/presentation/` |
| — | `lib/core/ui/` and the rest of `core/` |

`test/architecture/domain_purity_test.dart` scans imports and fails if a
Firebase SDK appears anywhere else. So Firebase cannot leak into the UI or the
domain model by accident, and a repository interface stays swappable.

### 5. Sharing is per (pair, user) and is read by the rules on every request

`pairs/{pairId}/sharing/{userId}` is the single source of truth for "is this
category shared right now". Security rules `get()` it (plus the pair document) to
authorize a partner read — at most two document lookups per request. Category
enablement is enforced on **write** (a disabled category is never stored) and
re-checked on **read** (a lingering field cannot become readable after sharing is
switched off). Location is a separate document so it can be gated independently
(NFR-036).

### 6. Privileged transitions are server-side, and nothing is a placeholder

No rule lets a client set `pairs.status = 'active'`. Pair activation therefore
requires the Admin SDK, and **no Cloud Functions project is scaffolded in
Phase 3** (justification in `FIREBASE_ARCHITECTURE.md` §7). The rules fail closed
without it, which is the correct behaviour for an unimplemented feature.

### 7. Rules are tested against the emulator, not assumed correct

`firebase/test/firestore.rules.test.js` runs 31 scenarios against the emulator
with the real rules loaded, covering unauthenticated access, user isolation, pair
isolation, category gating, paused/pending/revoked access, unauthorized writes and
append-only history.

## Consequences

Positive:

- The foundation is real and verifiable today: the SDK is integrated, the rules
  run and are proven, and the emulator workflow works without any account.
- No credential of any kind is required in the repository or the client.
- A missing or wrong project cannot silently half-initialize: it fails closed and
  logs a warning.
- iOS/Android builds are not blocked on a config file, and an operator can point
  at a real project by supplying four values.
- The architecture test keeps Firebase out of the domain and UI permanently.

Negative / accepted trade-offs:

- `google-services.json` is not used, so a future Firebase console app
  registration must be transcribed into `--dart-define` values rather than dropped
  in as a file. This is documented in `FIREBASE_ARCHITECTURE.md` §5.
- Emulator wiring lives in `core/firebase`, so that one file imports
  `cloud_firestore`/`firebase_auth` beyond initialization. Accepted: it is still
  inside the allowed boundary, and it is the only place emulator endpoints exist.
- Rules that `get()` a second document cost extra billed reads. Accepted: two
  lookups per partner read is far cheaper than the alternative of trusting the
  client, and it is the only way to enforce per-category sharing server-side.
- Until a Function exists, a pair cannot be activated, so pairing is not
  end-to-end demonstrable. Accepted deliberately (fail closed).

## Alternatives considered

- **Commit a `google-services.json` for a real project.** Rejected: no project
  exists, and committing a fabricated one would be both dishonest and misleading.
- **Apply the Google Services Gradle plugin without a JSON file.** Rejected: the
  build fails, and it would make the build depend on committing a config file.
- **Use `flutterfire configure` with a placeholder project.** Rejected: it
  requires an authenticated account and produces fabricated identifiers.
- **Trust the client for sharing decisions.** Rejected: it contradicts
  constraint 4 (client is not trusted) and the SRS requirement that authorization
  never depends on UI logic.
- **Denormalise sharing flags onto the pair document** (one fewer read).
  Rejected: two copies of the same fact can diverge, and the saved read is not
  worth a privacy bug.
- **Scaffold an empty Cloud Functions project.** Rejected: no behaviour, an extra
  toolchain and deploy target, and it would tempt implementing pairing logic in
  Phase 3.
