# Architecture

Mutual Device Presence & Reassurance System. This document describes the
architecture **as implemented** after Phase 3. Phase 1 built the domain foundation;
Phase 2 built the application architecture around it; Phase 3 added the Firebase
backend foundation (see §14 for the summary and the dedicated documents for detail).

Related documents:

- `docs/architecture/FIREBASE_ARCHITECTURE.md` — Firebase services, environments, boundaries.
- `docs/architecture/FIRESTORE_DATA_MODEL.md` — collections, ownership, retention.
- `docs/architecture/FIREBASE_SECURITY.md` — authorization model and Security Rules.
- `docs/platform/PLATFORM_CAPABILITIES.md` — what Android and iOS actually allow.
- `docs/requirements/REQUIREMENT_MAPPING.md` — SRS requirement → domain → phase.
- `docs/decisions/` — Architecture Decision Records.
- `docs/PHASE_01_COMPLETION_REPORT.md`, `docs/PHASE_02_COMPLETION_REPORT.md`, `docs/PHASE_03_COMPLETION_REPORT.md`.

---

## 1. Architectural style

A **feature-first layered architecture** with **Riverpod as the composition and
dependency-injection mechanism**.

- Code is organised by product feature under `lib/features/`.
- Each feature may contain `domain/`, `data/` and `presentation/` layers, created
  only when the feature needs them.
- Cross-cutting, feature-independent code lives in `lib/core/`.
- Composition (bootstrap, root widget, router, theme) lives in `lib/app/`.
- Dependencies point **inward and downward only**: `presentation → domain ← data`,
  `feature → core`, `app → features + core`. `core/` never depends on a feature.

Rationale and alternatives: `ADR-001-project-architecture.md`.

---

## 2. Directory structure (actual)

```
lib/
├── main.dart                       one-liner: AppBootstrap.run()
├── app/                            composition root
│   ├── app.dart                    KamApp (MaterialApp.router)
│   ├── bootstrap.dart              startup sequence
│   ├── error_boundary.dart         global build-error fallback
│   ├── providers.dart              core providers (config, clock, logger, platform)
│   ├── router/
│   │   ├── app_routes.dart         route names + paths
│   │   ├── app_router.dart         GoRouter definition + shell branches
│   │   ├── app_shell.dart          bottom-navigation shell
│   │   └── unknown_route_screen.dart
│   └── theme/
│       └── app_theme.dart          theme, typography and component conventions
├── core/
│   ├── constants/                  spacing/duration scale
│   ├── data/                       DataAvailability (shared availability flag)
│   ├── domain/                     DeviceMetric (shared metric vocabulary)
│   ├── error/                      AppException (thrown) + AppFailure (returned)
│   ├── extensions/                 DurationX formatting
│   ├── firebase/                   Firebase boundary (see §14): bootstrap,
│   │                               options, emulator wiring, error mapping
│   ├── freshness/                  DataFreshness + FreshnessPolicy
│   ├── logging/                    AppLogger abstraction + implementations
│   ├── platform/                   DevicePlatform, PlatformInfo
│   ├── result/                     Result<T> (Success / Failure) + guard
│   ├── time/                       Clock, DateTimeUtils
│   └── ui/                         shared presentation contract + widgets
│       ├── data_presentation_state.dart
│       ├── data_state_view.dart
│       ├── presentation_mapping.dart
│       └── widgets/                app_scaffold, app_card, app_button,
│                                   section_header, loading/error/empty/
│                                   unavailable views, freshness_indicator
└── features/
    ├── auth/          domain(models+repository) · data(repository impl) · presentation(profile, providers)
    ├── pairing/       domain(models)
    ├── device_state/  domain(models+capability+source) · data(source impl) · presentation(metric tile, providers)
    ├── (data/ layers are where Firebase SDKs are allowed to appear — §14)
    ├── location/      domain(models)
    ├── rules/         domain(models) · presentation(placeholder screen)
    ├── notifications/ domain(model)
    ├── dashboard/     presentation(screen)
    ├── privacy/       domain(models) · presentation(screen)
    └── history/       domain(model) · presentation(placeholder screen)
```

`lib/core/extensions/` holds only `DurationX`. There is deliberately **no**
`core/networking/`: Firestore is the transport, and the only HTTP-shaped client
(`cloud_firestore`/`firebase_auth`) is confined to `core/firebase/` and feature
`data/` layers (§14).

---

## 3. Application bootstrap

`main()` is one line; the sequence lives in `AppBootstrap` (`lib/app/bootstrap.dart`):

```
main()
  → AppBootstrap.initialize()   WidgetsFlutterBinding, AppConfig, logging, services
  → ProviderScope               installs provider overrides (config)
  → KamApp                      root widget
  → GoRouter                    initial route (dashboard)
```

Design rules:

- No initialization logic lives in a widget.
- `initialize()` returns the resolved `AppConfig` and is testable in isolation.
- `FirebaseBootstrap.initialize(config, logger:)` is the third step. It is
guarded: when Firebase is unconfigured or initialization fails it returns `false`
and logs, and the app continues offline. It never throws into startup.
- Services that do not exist yet (auth state, local persistence, notification
  handling, background monitoring registration) have a commented slot in the
  sequence rather than speculative code.
- `AppErrorBoundary.install()` replaces Flutter's error widget with a calm
  fallback so a broken subtree does not show a red screen.

---

## 4. Configuration and environment

- Compile-time configuration through `--dart-define`, read once into `AppConfig`.
- `APP_ENV` (`development` | `staging` | `production`, default `development`),
  `ENABLE_VERBOSE_LOGGING`.
- Firebase client identifiers: `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`,
  `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, plus optional
  `FIREBASE_AUTH_DOMAIN` / `FIREBASE_STORAGE_BUCKET` and the emulator switch
  `FIREBASE_USE_EMULATORS`. All four core identifiers are required together; a
  partial set counts as *not configured*, so a mistake fails closed.
- Values reach widgets only through `appConfigProvider`; nothing reads the
  compiler environment inside the UI.
- **Client-safe**: Firebase project id, API key, app id, sender id, API base URLs,
  feature flags. These identify a project and are not credentials.
- **Never client-side**: Firebase Admin/service-account credentials, private API
  keys, Cloud Functions secrets. `.gitignore` also blocks `*.env`, `*.pem`,
  `*.jks`, `service-account*.json` as defence in depth.

See `ADR-004-configuration-strategy.md`.

---

## 5. Dependency injection

**Riverpod is the DI container.** There is no custom DI framework, no service
locator, and no `get_it`.

| Seam | Provider | Default (Phase 2) |
| --- | --- | --- |
| Configuration | `appConfigProvider` (`app/providers.dart`) | must be overridden at runtime |
| Firebase initialization | `FirebaseBootstrap.initialize()` result, consumed in `bootstrap.dart` | `false` when unconfigured |
| Time | `clockProvider` | `SystemClock` |
| Logging | `loggerProvider` | `DeveloperAppLogger` (level from config) |
| Platform detection | `platformInfoProvider` | `FlutterPlatformInfo` |
| Identity | `authRepositoryProvider` (`features/auth/.../auth_providers.dart`) | `UnauthenticatedAuthRepository` |
| Device state | `deviceStateSourceProvider` (`features/device_state/.../device_state_providers.dart`) | `UnavailableDeviceStateSource` |

Rules:

- Repositories and platform sources are exposed as providers, so tests override
  them with fakes and later phases swap in Firebase/native implementations
  without touching UI.
- Providers that must be replaced at startup (`appConfigProvider`) throw if not
  overridden, which fails loudly instead of silently using a wrong default.
- Feature-local providers live with their feature; only genuinely
  cross-cutting providers live in `app/providers.dart`.

See `ADR-005-dependency-injection-and-error-handling.md`.

---

## 6. Routing and the navigation shell

`go_router` with a `StatefulShellRoute.indexedStack`:

```
/                dashboard    ┐
/rules           rules        ├─ shell branches (bottom navigation, own state)
/history         history      │
/privacy         privacy      ┘
/profile         profile      ← pushed above the shell
/sign-in, /pairing            ← reserved names for the Phase 4 auth guard
```

- Route names and paths live in `AppRoutes` (`app/router/app_routes.dart`); no
  widget uses a string literal path.
- Authentication-aware navigation is supported by passing a `redirect` callback
  to `createAppRouter()`. Phase 4 supplies the guard; no route needs restructuring.
- Unmatched locations render `UnknownRouteScreen` via `errorBuilder`.
- The shell holds no business state; each branch screen owns its own `AppBar` and
  content through `AppScaffold`.

---

## 7. State management

Two clearly separated kinds of state:

### Ephemeral UI state
Selected tab, dialog visibility, form fields, local loading flags. Lives in the
widget (`StatefulWidget`, `TextEditingController`) or in a local provider scoped
to the screen. The navigation shell owns the selected branch itself.

### Application / domain state
Signed-in user, pair connection state, partner device state, rules, location,
history. Owned by providers that wrap a repository/source, never held in widgets:

| State | Provider | Shape |
| --- | --- | --- |
| Current user | `currentUserProvider` | `StreamProvider<AppUser?>` |
| Device capabilities | `deviceCapabilityReportProvider`, `deviceCapabilityProvider` | `Provider<DeviceCapabilityReport>`, `Provider.family<MetricSupport, DeviceMetric>` |
| Own device state | `currentDeviceStateProvider` | `FutureProvider<Result<DeviceState>>` |

There is **no single global app-state object**. Each concern has its own provider
so a failure in one cannot freeze another.

### Asynchronous state contract

Riverpod 3 allows an `AsyncValue` to be *loading and failed at the same time*.
`AsyncValue.when` therefore shows a spinner and can hide an error that has already
arrived. All screens therefore go through
`PresentationMapping` (`core/ui/presentation_mapping.dart`), which checks
`hasValue` and then `hasError` and returns a `DataPresentation`. See
`ADR-006-state-scoping-and-async-presentation.md`.

---

## 8. Error and result handling

Two distinct types, intentionally:

| Type | Used for | Lives in |
| --- | --- | --- |
| `AppException` (sealed) | **thrown** by low-level/plugin/SDK code | `core/error/app_exception.dart` |
| `AppFailure` (sealed) | **returned** inside `Result` once classified and made user-safe | `core/error/app_failure.dart` |
| `Result<T>` (`Success`/`Failure`) | repository/source return type | `core/result/result.dart` |

- `Result.guard(() async …)` / `guardSync` convert a thrown error into a
  classified `Failure`, so `try/catch (_) {}` patterns are not needed.
- `AppFailure.fromException` maps exception kinds to failure kinds
  (`permission`, `configuration`, `remoteService`, `unsupportedCapability`,
  …) and maps anything unknown to a generic message while retaining the original
  error in `cause` for logging only. Internals are never shown to the user.
- `FirebaseErrorMapper` (`core/firebase/firebase_error_mapper.dart`) performs the
  SDK-specific half: it converts `FirebaseException`/`FirebaseAuthException`
  codes (plus plugin `PlatformException`s and `SocketException`) into
  `AppException` types and user-safe messages. It is a pure function, so it is unit
  tested without any Firebase connection.
- The UI never branches on exception types: it renders a `DataPresentation`.

Exhaustiveness is the point: `Result` and `AppFailure` are `sealed`, so a new
failure category is a compile-time error until it is handled.

---

## 9. Device-state abstraction and platform isolation

```
presentation  →  deviceStateSourceProvider  →  DeviceStateSource (interface)
                                                      ├── UnavailableDeviceStateSource (Phase 2)
                                                      ├── AndroidDeviceStateSource     (Phase 5)
                                                      └── IosDeviceStateSource         (Phase 5)
```

- `DeviceStateSource` (`features/device_state/domain/sources/`) declares
  `capabilities` and `readCurrentState()`. It returns `Result`, never throws.
- `DeviceCapabilityReport` states per metric whether the platform is
  `supported`, `requiresPermission` or `unsupported`. Missing metrics default to
  **unsupported**, so an unknown platform degrades honestly instead of being
  assumed capable (FR-068, NFR-019).
- Platform detection itself is behind `PlatformInfo`; `FlutterPlatformInfo` is the
  only place reading `defaultTargetPlatform`.
- `UnavailableDeviceStateSource` is the Phase 2 default. It is **not** a fake: it
  reports every capability as unsupported and returns an all-unknown
  `DeviceState`. It never invents a battery level, charging state or location.
- No `watch()`/stream method is declared yet: promising a real-time stream before
  the background-execution strategy exists would overstate what the platforms
  allow. It arrives in Phase 5.

See `docs/platform/PLATFORM_CAPABILITIES.md` and
`ADR-003-device-state-model.md`.

---

## 10. Shared domain vocabulary

| Type | Location | Why shared |
| --- | --- | --- |
| `DataAvailability` | `core/data/` | Availability applies to any remotely observed data, and `core/ui` needs it without depending on a feature |
| `DataFreshness`, `FreshnessPolicy` | `core/freshness/` | Freshness is a cross-cutting honesty rule (NFR-025) |
| `DevicePlatform` | `core/platform/` | Needed by both platform detection and the device model |
| `DeviceMetric` | `core/domain/` | Canonical "what can be observed" vocabulary for capability reporting |

Typed identifier wrappers (`UserId`, `PairId`, `DeviceId`, …) were **deliberately
not introduced**. They would require migrating every Phase 1 model and test for a
bug class that clear naming already handles at this scale; the Phase 2 brief
explicitly cautions against types that only wrap primitives. This can be revisited
if and when identifier mix-ups actually occur.

---

## 11. Time handling

- `Clock` (`core/time/clock.dart`) is injected via `clockProvider`. Business and
  presentation code never calls `DateTime.now()` directly, so freshness and
  (later) rule evaluation are deterministic under test (`FixedClock`).
- Persisted and exchanged timestamps are **UTC**. Conversion to local time happens
  only in `DateTimeUtils.formatLocalTimestamp` at display time (NFR-026).
- `DurationX` (`core/extensions/duration_x.dart`) and `DateTimeUtils` provide the
  single formatting path for charging duration, offline duration, location age and
  event timestamps.

---

## 12. Shared UI foundation and data-state presentation rules

**Presentation contract.** `DataPresentation` + `DataPresentationState`
(`core/ui/`) is the one vocabulary for loading, empty, loaded, failure, unknown,
unsupported, unavailable and paused. `DataStateView` renders it exhaustively and
is the only place these cases are handled.

```
DataPresentationState   meaning                                   rendered by
──────────────────────  ────────────────────────────────────────  ──────────────────
loading                 read in flight                             LoadingView
empty                   success with genuinely nothing            EmptyView
loaded                  a real value exists                        caller + freshness
failure                 read failed (safe message)                 ErrorView (+retry)
unknown                 supported, value undeterminable            UnavailableView
unsupported             platform cannot provide it (FR-068)        UnavailableView
unavailable             temporarily inaccessible (FR-056)          UnavailableView
paused                  owner paused sharing (FR-053)              UnavailableView
```

Freshness is a **property of loaded data**, not a separate state:
`FreshnessIndicator` renders "Updated 12 seconds ago" / "Last updated 2h 13m ago"
and uses an error-coloured icon for stale values. `MetricTile`
(`features/device_state/presentation/widgets/`) combines a metric's value, its
non-available state and its freshness, which is where "Battery: Unknown" instead
of "Battery: 0%" is enforced (FR-048).

**Widgets** in `core/ui/widgets/`: `AppScaffold`, `AppCard`, `AppButton`,
`SectionHeader`, `LoadingView`, `ErrorView`, `EmptyView`, `UnavailableView`,
`FreshnessIndicator`. All state is conveyed by text or icon as well as colour
(NFR-028), and text uses the Material 3 `TextTheme` so system text scaling works.

---

## 13. Logging

- `AppLogger` (`core/logging/`) with `debug` / `info` / `warning` / `error`.
- `DeveloperAppLogger` (structured `dart:developer` output, level-gated) is the
  default; `NoopAppLogger` discards output. Swappable per environment via
  `loggerProvider`.
- `sanitizeContext` redacts values whose keys indicate sensitive data (tokens,
  passwords, email, coordinates), as defence in depth for NFR-045. Callers are
  still responsible for not passing secrets.
- Level is derived from configuration, so a production build emits less without
  any call-site change.

---

## 14. Firebase boundaries (Phase 3)

The responsibility split is unchanged from Phase 1 (`ADR-002`)
and made concrete by `ADR-007`. Full detail lives in the three dedicated
documents; this section is the map.

| Document | Answers |
| --- | --- |
| `FIREBASE_ARCHITECTURE.md` | Which services, which environments, how the client connects, offline/cost/error strategy |
| `FIRESTORE_DATA_MODEL.md` | Which collections, what they hold, who owns them, retention |
| `FIREBASE_SECURITY.md` | Who may read/write what, and why the rules are trustworthy |

### What is integrated

- `lib/core/firebase/` is the only Firebase-aware part of `core/`:
  `firebase_config.dart` (options from config), `firebase_bootstrap.dart`
  (guarded init), `firebase_emulators.dart` (emulator endpoints),
  `firebase_error_mapper.dart` (SDK errors → `AppException`).
- Firebase initialization is one call in `AppBootstrap`, is failure-tolerant, and
  no widget ever initializes or touches it.
- **A test enforces the boundary**: `test/architecture/domain_purity_test.dart`
  fails if a Firebase SDK is imported outside `core/firebase/` or a feature
  `data/` layer. The UI and the domain layer cannot acquire a Firebase dependency
  by accident.

### Where data flows

```
widget → provider → repository interface (domain) → data source (data/)
                                                        ↓
                                          Firestore / Firebase Auth / FCM
```

The presentation layer knows only provider types and `Result`/`AppFailure`; it
never sees a `FirebaseException`, a `DocumentSnapshot` or a collection path.

### Trust split

| Concern | Client | Server (Security Rules / Admin SDK) |
| --- | --- | --- |
| Observation (battery, charging, network, location) | ✅ collects | — |
| Reading own profile, pair, partner's shared state | reads, gated by rules | — |
| **Authorization** (pair membership, category sharing) | displays only | ✅ enforced on every request |
| Pair activation | ❌ cannot | ✅ Admin SDK / Cloud Function |
| Interpreting state (rules) | evaluates for display | may later re-evaluate |

`pairs.status` is never client-settable, so a client cannot join a pair, a partner
cannot read a paused/revoked pair, and a client cannot widen its own sharing. The
rules are tested against the emulator (31 scenarios, `FIREBASE_SECURITY.md` §7).

### Still not implemented

No authentication flow (Phase 4), no pairing/consent workflow (Phase 5), no device
monitoring (Phase 6), no Cloud Functions project, no FCM registration. Phase 3
prepared their structure and the security model they must obey.

Facts and interpretations never mix: `ValueOrigin` / `MetricValue.isInterpretation`
and `Interpretation.isObjectiveFact` make the distinction part of the type system,
and `pairs/*/rules` stores a user-defined `probabilityPercent` separately from any
future model-generated estimate (`FIRESTORE_DATA_MODEL.md` §8).

---

## 15. Security and privacy boundaries

- Consent ≠ pairing; a pairing code grants nothing (`Consent`, `ConsentRequest`).
- Pair isolation: `Pair.partnerOf` throws for a non-member; the real enforcement
  is Firestore Security Rules in Phase 12.
- Category-level sharing via `SharingPreferences`; pausing is independent per
  category and does not disconnect the pair.
- `MetricValue.asUnavailable()` keeps provenance but drops the live value, so a
  revoked permission cannot be shown as a current value.
- No secrets in the client; configuration is client-safe only.

---

## 16. Testing strategy

| Layer | Tests | Notes |
| --- | --- | --- |
| Domain models | `test/unit/*` | Pure Dart, no plugins |
| Freshness/time | `test/unit/freshness_test.dart`, `date_time_utils_test.dart`, `duration_x_test.dart` | `FixedClock` keeps them deterministic |
| Result/errors | `test/unit/result_test.dart`, `app_failure_test.dart` | Includes "internals are not leaked" |
| Async → presentation | `test/unit/presentation_mapping_test.dart` | Covers the Riverpod 3 loading+error case |
| UI states | `test/widget/data_state_view_test.dart` | loading / failure / empty / unknown / unsupported / unavailable / paused / stale |
| Routing | `test/widget/router_test.dart` | initial route, branch navigation, profile push, unknown route |
| DI seams | `test/widget/profile_screen_test.dart` | `AuthRepository` replaced by a fake (signed out, signed in, failure) |
| Startup | `test/unit/app_startup_test.dart` | Bootstrap resolves config, never throws without Firebase |
| Firebase config/errors | `test/unit/firebase_config_test.dart`, `firebase_error_mapper_test.dart` | Options assembly, partial config fails closed, SDK error classification |
| Architecture | `test/architecture/domain_purity_test.dart` | Domain purity, `core` ↛ features, Firebase confined to `core/firebase/` + `data/` |
| Firestore Security Rules | `firebase/test/firestore.rules.test.js` | 31 emulator scenarios (unauthenticated, isolation, sharing gates, unauthorized writes) |

Doubles live in `test/fakes/` (`FakeAuthRepository`, `FakeDeviceStateSource`,
`RecordingLogger`) and helpers in `test/support/test_app.dart`
(`pumpTestApp`, `fixedClock`). Flutter tests never touch Firebase, the network or
real device APIs — Firebase behaviour is covered by pure functions (config, error
mapping) and by the emulator suite, which is where rules must be proven.

---

## 17. Changes to Phase 1 decisions (documented)

Phase 2 preserved every Phase 1 domain model. Three structural changes were made,
all recorded here because Phase 1 constraints require changes to be justified:

| Change | Reason |
| --- | --- |
| `DevicePlatform` moved from `features/device_state/domain/models/device.dart` to `core/platform/device_platform.dart` | `core/` must not depend on a feature, and platform detection needs it |
| `DataAvailability` moved from `metric_value.dart` to `core/data/data_availability.dart` | `core/ui` needs it without importing a feature |
| `core/errors/` consolidated into `core/error/` | One error home (`AppException` + `AppFailure`), matching the Phase 2 structure |
| `lib/app/router.dart` → `lib/app/router/`, `lib/app/theme.dart` → `lib/app/theme/` | Routing and theming grew beyond one file (shell, routes, unknown route) |

None of these changed a model's meaning or behaviour; all Phase 1 tests still pass.

Phase 3 changed no existing architecture. It added `lib/core/firebase/` and
`lib/firebase/` configuration, plus one new architecture rule (Firebase may appear
only in `core/firebase/` and feature `data/` layers) recorded in ADR-007. The
Phase 2 placeholder `DeviceStateSource`/`AuthRepository` implementations are
untouched and remain the defaults until Phases 4–6 replace them.

---

## 18. Future extensibility

- **New metrics** (NFR-040): add a `DeviceMetric`, a field on `DeviceState`, a
  capability entry, a collector. No rule-engine or UI redesign.
- **New screens**: add a `GoRoute` (and a branch if it is a primary destination).
- **Authentication**: implement `AuthRepository`, add the `redirect` guard, add
  sign-in/pairing routes already reserved in `AppRoutes`.
- **New platform**: `DevicePlatform.unknown` plus explicit capability states mean
  a new platform degrades to "unsupported" instead of misreporting.
- **Server-side rule evaluation**: rule definitions are data, so moving the
  evaluator changes where it runs, not what a rule is.

---

## 19. Explicit non-goals so far

No authentication, pairing, device monitoring, location tracking, rule evaluation,
notifications or event history has been implemented. There is no Cloud Functions
project and no FCM registration.

What exists is the structure those features plug into: bootstrap, DI seams, routing
shell, result/error handling, platform abstraction, shared UI, logging, the tests
that hold the boundaries, and (Phase 3) a secure Firestore foundation with
enforced pair-scoped authorization.
