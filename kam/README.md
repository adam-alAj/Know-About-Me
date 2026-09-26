# Know About Me (`kam`)

A private, consent-based **Mutual Device Presence & Reassurance** app for two
people who are physically separated. Each user explicitly connects their device
with one other user and can then see a limited, authorized view of the other's
**observed device state** (battery, charging, connectivity, last online, activity
and, where permitted, location), plus **interpretations** produced from rules the
user defines themselves.

The app is **not** a messaging, social or tracking app. It is a reassurance view
built from measurable device indicators.

> **Facts vs interpretations.** `Phone has been charging for 4 hours` is an
> observed fact. `There is a 70% possibility that Afraa is sleeping now` is a
> **user-defined rule interpretation** and is never presented as a fact.

The product specification is the SRS at [`../Docs/SRS_DOC.md`](../Docs/SRS_DOC.md).
It is the primary source of truth.

---

## Status

| Phase | Scope | State |
| --- | --- | --- |
| 1 | Foundation: project, domain models, tests, docs | ✅ Complete |
| 2 | Application architecture: bootstrap, DI, routing shell, error handling, platform abstraction, shared UI, logging, architecture tests | ✅ Complete |
| 3 | Firebase foundation: FlutterFire integration, environment strategy, Firestore data model, Security Rules + emulator tests, emulator workflow, error mapping | ✅ Complete |
| 4 | Authentication + user profile: registration, sign-in, sign-out, session restoration, guarded routing, profile documents | ✅ Complete |
| 4b | **Spark-only correction**: no mandatory Cloud Functions / billing dependency; activation and pairing codes are rule-enforced, rule evaluation is client-side, and notification boundaries are documented | ✅ Complete |
| 5 | Pairing, consent and connection lifecycle (no server needed: the rules gate activation on both consent documents) | Next |

Not implemented yet (deliberately): pairing, device monitoring, location tracking,
the rule *management* UI, remote push notifications, and history. The rule
*evaluator* and notification-planning boundary exist, but the default local
notification service reports unsupported until a platform plugin is added. The
shell renders unfinished areas with explicit empty/unknown states rather than
fabricated data.

The backend is designed for the **Firebase Spark (no-cost) plan**: no Cloud
Functions, Cloud Run, or billing account is required by this architecture. No
live Firebase project is configured yet. See
[`docs/architecture/SPARK_ONLY_ARCHITECTURE.md`](docs/architecture/SPARK_ONLY_ARCHITECTURE.md)
and [`docs/SPARK_COMPATIBILITY_CHECKLIST.md`](docs/SPARK_COMPATIBILITY_CHECKLIST.md).

See [`docs/PHASE_01_COMPLETION_REPORT.md`](docs/PHASE_01_COMPLETION_REPORT.md) …
[`docs/PHASE_04_COMPLETION_REPORT.md`](docs/PHASE_04_COMPLETION_REPORT.md).

---

## Requirements

- **Flutter** 3.44.8 (stable channel) — see `flutter --version`
- **Dart** 3.12.2
- Android tooling with an SDK (for Android builds); macOS + Xcode for iOS builds
- **Node.js 18+** and the **Firebase CLI** with a JDK 11+ — only for the Firestore
  Security Rules tests and the emulator suite (Firebase packages are no longer optional;
  the app compiles and runs without a Firebase project: see *Configuration* below)

## Getting started

```bash
cd kam
flutter pub get
flutter run                 # runs on the connected device / emulator
```

Useful commands:

```bash
flutter analyze             # static analysis
flutter test                # unit, widget and architecture tests
dart format --output=none --set-exit-if-changed .   # formatting check
flutter build apk --debug    # Android debug build
```

### Configuration

Configuration is compile-time via `--dart-define` (see
`docs/decisions/ADR-004-configuration-strategy.md` and
`docs/architecture/FIREBASE_ARCHITECTURE.md`):

```bash
flutter run --dart-define=APP_ENV=development --dart-define=ENABLE_VERBOSE_LOGGING=true
```

| Key | Values | Default |
| --- | --- | --- |
| `APP_ENV` | `development` \| `staging` \| `production` | `development` |
| `ENABLE_VERBOSE_LOGGING` | `true` \| `false` | `true` outside production |
| `FIREBASE_PROJECT_ID` | Firebase project id | unset |
| `FIREBASE_API_KEY` | Firebase web/Android API key (client-safe) | unset |
| `FIREBASE_APP_ID` | Firebase app id | unset |
| `FIREBASE_MESSAGING_SENDER_ID` | Firebase app sender identifier required by `FirebaseOptions` (does not wire FCM) | unset |
| `FIREBASE_AUTH_DOMAIN`, `FIREBASE_STORAGE_BUCKET` | optional, for web/storage | unset |
| `FIREBASE_USE_EMULATORS` | `true` \| `false` | `false` |

All four required Firebase values must be supplied together; a partial set is
treated as **not configured**, so the app fails closed instead of connecting to the
wrong project. With no values the app runs offline and every remote read reports an
explicit non-available state.

Firebase is wired through explicit `FirebaseOptions` rather than a committed
`google-services.json`, so the repository needs **no** project-specific config file.

Never place secrets in `--dart-define` values. Those values reach the client and
are public by construction. Server-side credentials (Firebase Admin service
accounts, private API keys) must stay on the server.

---

## Project structure

```
kam/
├── lib/
│   ├── main.dart              one-liner entry → AppBootstrap.run()
│   ├── app/                   composition root
│   │   ├── app.dart           root widget
│   │   ├── bootstrap.dart     startup sequence
│   │   ├── error_boundary.dart
│   │   ├── providers.dart     config, clock, logger, platform
│   │   ├── router/            routes, router, auth guard, shell, unknown route
│   │   └── theme/             theme + typography conventions
│   ├── core/                  cross-cutting, feature-independent
│   │   ├── config/  data/  domain/  error/  extensions/
│   │   ├── firebase/          options, guarded bootstrap, emulators, error mapping
│   │   ├── freshness/  logging/  platform/  result/  time/
│   │   └── ui/                presentation contract + shared widgets
│   └── features/              one directory per product feature│   ├── auth/              identity + profile: domain(models, repositories,
│   │                      service, validation) · data(Firebase auth repo,
│   │                      Firestore profile repo) · presentation(splash,
│   │                      sign-in, create-account, profile, providers)
│       ├── pairing/           pairs, pairing codes, consent, lifecycle
│       ├── device_state/      device identity, state, capability, source
│       ├── location/          coordinates, home location, presence
│       ├── rules/             rule engine models + placeholder screen
│       ├── notifications/     notification records
│       ├── dashboard/         reassurance screen
│       ├── privacy/           sharing categories + screen
│       └── history/           event history model + placeholder screen
├── test/
│   ├── architecture/          dependency-boundary tests
│   ├── fakes/                 test doubles
│   ├── support/               pumpTestApp / fixedClock helpers
│   ├── unit/                  domain, result, error, time, presentation tests
│   ├── widget/                routing, data-state and DI-seam tests
│   └── widget_test.dart       launch smoke tests
├── assets/                    images/ and branding/
├── firebase/                  security rules, indexes, rules tests (see its README)
├── docs/                      architecture, platform, requirements, decisions
├── firebase.json  .firebaserc Firebase CLI config (local `demo-kam` by default)
├── android/  ios/             platform projects
└── pubspec.yaml
```

Each feature may contain `domain/`, `data/` and `presentation/` layers.
`domain/` is pure Dart — a test enforces that it never imports Flutter, Riverpod,
go_router or Firebase.

---

## Dependencies

| Package | Why | Requirement |
| --- | --- | --- |
| `flutter_riverpod` (`^3.4.3`) | State management **and** dependency injection | NFR-017, NFR-018 |
| `go_router` (`^17.5.0`) | Declarative routing with shell branches and future auth guards | NFR-017 |
| `intl` (`^0.20.3`) | Date/time formatting and localization groundwork | NFR-026, NFR-027 |
| `firebase_core`, `firebase_auth`, `cloud_firestore` | Identity and synchronized persistence | FR-001, FR-072, NFR-007, NFR-010 |
| `flutter_lints` (dev) | Recommended lint set | NFR-017 |
| `@firebase/rules-unit-testing` (dev, Node) | Proves the Firestore Security Rules against the emulator | NFR-005, NFR-007, NFR-009 |

**Phase 4 added no dependency**: authentication and the profile are built on the
FlutterFire packages and the shared UI that already existed.

Every dependency is justified in `docs/architecture/FIREBASE_ARCHITECTURE.md` §2 or
`ADR-001`/`ADR-007`. `google-services.json` and `GoogleService-Info.plist` are
**not** used, which is why the Android build needs no Google Services Gradle plugin.

---

## Known limitations

- **Authentication exists but cannot be exercised end-to-end here.** With no
  Firebase project configured the app shows "Accounts are unavailable" and
  disables sign-in — the honest state, not a bug. A real end-to-end run also needs
  an Android emulator/device (FlutterFire does not support Windows desktop), which
  this environment does not have. See
  [`docs/PHASE_04_COMPLETION_REPORT.md`](docs/PHASE_04_COMPLETION_REPORT.md) §6.1.
- **A cold-start deep link to a protected route** is replaced by splash →
  dashboard, because the guard never renders protected content before the session
  is known. No deep links are configured yet.
- **Password reset, email verification and account deletion are not implemented.**
- **No real Firebase project is configured.** The SDK is integrated and the
  foundation is secure, but until project ids are supplied via `--dart-define` the
  app runs offline against no backend. See
  `docs/PHASE_03_COMPLETION_REPORT.md` for the exact remaining manual step.
- **No Cloud Functions project, and none is planned.** The architecture is
  designed for Spark; no live project is configured. Pair activation is enforced
  by Firestore
  Security Rules requiring **both** members' consent documents instead of by a
  server. See
  [`docs/architecture/SPARK_ONLY_ARCHITECTURE.md`](docs/architecture/SPARK_ONLY_ARCHITECTURE.md).
  Remote push notifications and cross-user retention/cleanup are deferred for the
  same reason and are documented, not simulated.
- No authentication, pairing, monitoring, location, rule evaluation or
  notifications. The rules/history/privacy screens are placeholders.
- The dashboard shows `Unknown` for every device metric, which is the correct
  behaviour when no collector exists yet.
- **iOS build is not validated** in the current Windows environment: on Windows
  `flutter build ios` is not even available as a subcommand. A macOS + Xcode
  machine is required. Android debug builds succeed.

Platform caveats that are by design, not bugs:

- A phone's powered-off state cannot be detected on Android or iOS, so the app
  never claims it (see `docs/platform/PLATFORM_CAPABILITIES.md`).
- Screen state cannot be observed on iOS and is only partly observable on Android.
- Background collection is best-effort on both platforms, so data age is always
  shown.

## Documentation- [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md)
- [`docs/architecture/AUTHENTICATION_ARCHITECTURE.md`](docs/architecture/AUTHENTICATION_ARCHITECTURE.md)
- [`docs/architecture/USER_PROFILE_MODEL.md`](docs/architecture/USER_PROFILE_MODEL.md)
- [`docs/architecture/FIREBASE_ARCHITECTURE.md`](docs/architecture/FIREBASE_ARCHITECTURE.md)
- [`docs/architecture/FIRESTORE_DATA_MODEL.md`](docs/architecture/FIRESTORE_DATA_MODEL.md)
- [`docs/architecture/FIREBASE_SECURITY.md`](docs/architecture/FIREBASE_SECURITY.md)
- [`docs/platform/PLATFORM_CAPABILITIES.md`](docs/platform/PLATFORM_CAPABILITIES.md)
- [`docs/requirements/REQUIREMENT_MAPPING.md`](docs/requirements/REQUIREMENT_MAPPING.md)
- [`docs/decisions/`](docs/decisions/)
- [`docs/PHASE_01_COMPLETION_REPORT.md`](docs/PHASE_01_COMPLETION_REPORT.md)
- [`docs/PHASE_02_COMPLETION_REPORT.md`](docs/PHASE_02_COMPLETION_REPORT.md)- [`docs/PHASE_03_COMPLETION_REPORT.md`](docs/PHASE_03_COMPLETION_REPORT.md)
- [`docs/PHASE_04_COMPLETION_REPORT.md`](docs/PHASE_04_COMPLETION_REPORT.md)
- [`firebase/README.md`](firebase/README.md) — emulator commands and rules tests

## What comes next (Phase 5)

Pairing, consent and the connection lifecycle. The data model and the pair-scoped
Security Rules already exist and are tested; the missing piece is the server-side
activation step — a Cloud Function that validates both consent documents in a
transaction and sets `pairs.status = 'active'`, because no client is allowed to.
The `/pairing` route is already guarded, and the Phase 1 `PairingCode`/`Consent`
models and `SharingPreferences` map onto the stored documents 1:1.
