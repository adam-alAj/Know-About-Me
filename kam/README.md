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
| 3 | Firebase project + authentication + profile | Next |

Not implemented yet (deliberately): authentication, Firebase backend, pairing,
device monitoring, location tracking, rule evaluation, notifications, history.
The shell renders those areas with explicit empty/unknown states rather than
fabricated data.

See [`docs/PHASE_01_COMPLETION_REPORT.md`](docs/PHASE_01_COMPLETION_REPORT.md) and
[`docs/PHASE_02_COMPLETION_REPORT.md`](docs/PHASE_02_COMPLETION_REPORT.md).

---

## Requirements

- **Flutter** 3.44.8 (stable channel) — see `flutter --version`
- **Dart** 3.12.2
- Android tooling with an SDK (for Android builds); macOS + Xcode for iOS builds
- (Phase 3+) a Firebase project

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
`docs/decisions/ADR-004-configuration-strategy.md`):

```bash
flutter run --dart-define=APP_ENV=development --dart-define=ENABLE_VERBOSE_LOGGING=true
```

| Key | Values | Default |
| --- | --- | --- |
| `APP_ENV` | `development` \| `staging` \| `production` | `development` |
| `ENABLE_VERBOSE_LOGGING` | `true` \| `false` | `true` outside production |
| `FIREBASE_PROJECT_ID` | public Firebase project id | unset (Phase 2) |

Never place secrets in `--dart-define` values that reach the client. Server-side
credentials (Firebase Admin, private API keys) must stay on the server.

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
│   │   ├── router/            routes, router, navigation shell, unknown route
│   │   └── theme/             theme + typography conventions
│   ├── core/                  cross-cutting, feature-independent
│   │   ├── config/  data/  domain/  error/  extensions/  firebase/
│   │   ├── freshness/  logging/  platform/  result/  time/
│   │   └── ui/                presentation contract + shared widgets
│   └── features/              one directory per product feature
│       ├── auth/              identity: models, repository, providers, screen
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
├── docs/                      architecture, platform, requirements, decisions
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
| `flutter_lints` (dev) | Recommended lint set | NFR-017 |

No dependency was added in Phase 2: the architecture was built with what Phase 1
already justified. Firebase packages are deliberately still absent — see
`docs/decisions/ADR-002-firebase-boundaries.md`.

---

## Known limitations

- No Firebase connection; the app runs offline with placeholder data.
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

## Documentation

- [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md)
- [`docs/platform/PLATFORM_CAPABILITIES.md`](docs/platform/PLATFORM_CAPABILITIES.md)
- [`docs/requirements/REQUIREMENT_MAPPING.md`](docs/requirements/REQUIREMENT_MAPPING.md)
- [`docs/decisions/`](docs/decisions/)
- [`docs/PHASE_01_COMPLETION_REPORT.md`](docs/PHASE_01_COMPLETION_REPORT.md)
- [`docs/PHASE_02_COMPLETION_REPORT.md`](docs/PHASE_02_COMPLETION_REPORT.md)

## What comes next (Phase 3)

Create the Firebase project (Auth + Firestore + FCM), add the FlutterFire
dependencies, replace the `FirebaseBootstrap` no-op with real initialization, and
implement `AuthRepository` against Firebase Auth plus the profile flow — then add
the authentication redirect guard to `createAppRouter()`. Nothing in Phases 1–2
needs re-architecting to begin.
