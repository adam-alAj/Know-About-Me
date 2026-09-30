# Architecture

> **Scope note:** This is the Phase 1–4 architecture baseline, not a complete
> as-built description after later implementation phases. Pairing, monitoring,
> location, rules UI, history, Android notifications, privacy controls, offline
> recovery, and production hardening were added later. Use
> [`../project/FINAL_PROJECT_HANDOVER.md`](../project/FINAL_PROJECT_HANDOVER.md)
> and focused current documents for implementation status. Phase 2 project and
> validation statements below are historical.

Mutual Device Presence & Reassurance System. This document describes the
architecture **as implemented** after Phase 4. Phase 1 built the domain foundation;
Phase 2 built the application architecture around it; Phase 3 added the Firebase
backend foundation; Phase 4 added authentication and the user profile
(§20 summarises it; the dedicated documents have the detail).

Related documents:

- `docs/architecture/AUTHENTICATION_ARCHITECTURE.md` — identity, auth state, router guard.
- `docs/architecture/USER_PROFILE_MODEL.md` — profile documents, ownership, write paths.
- `docs/architecture/FIREBASE_ARCHITECTURE.md` — Firebase services, environments, boundaries.
- `docs/architecture/FIRESTORE_DATA_MODEL.md` — collections, ownership, retention.
- `docs/architecture/FIREBASE_SECURITY.md` — authorization model and Security Rules.
- `docs/platform/PLATFORM_CAPABILITIES.md` — what Android and iOS actually allow.
- `docs/requirements/REQUIREMENT_MAPPING.md` — SRS requirement → domain → phase.
- `docs/decisions/` — Architecture Decision Records.
- `docs/PHASE_01_COMPLETION_REPORT.md` … `docs/PHASE_04_COMPLETION_REPORT.md`.

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
│   │                               + appRouterProvider / appInitialLocationProvider
│   ├── router/
│   │   ├── app_routes.dart         route names + paths
│   │   ├── app_router.dart         GoRouter definition, shell branches, router provider
│   │   ├── auth_redirect.dart      pure authentication guard (see §20)
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
│   │                               options, emulator wiring, error mapping,
│   │                               and the raw SDK handles as providers
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
│                                   section_header, app_inline_message,
│                                   loading/error/empty/unavailable views,
│                                   freshness_indicator
└── features/
    ├── auth/          identity + profile (see §20):
    │                  domain(models, repositories, service, validation)
    │                  data(Firebase auth repo, Firestore profile repo,
    │                       unavailable repos) · presentation(splash, sign-in,
    │                       create-account, profile, providers)
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
- Authentication state is **not** initialized here: it is pushed by the provider
  and mirrored by `AuthController`, so there is exactly one code path for a warm
  start and a cold start (see `AUTHENTICATION_ARCHITECTURE.md` §3).
- Services that do not exist yet (local persistence, notification handling,
  background monitoring registration) have a commented slot in the sequence
  rather than speculative code.
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
  keys, and any credential that could send a push. There is no Cloud Functions
  project to hold a secret, which is the point of the Spark-only architecture.
  `.gitignore` also blocks `*.env`, `*.pem`,
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
| Identity | `authRepositoryProvider` (`features/auth/presentation/providers/`) | `FirebaseAuthRepository`, or `UnavailableAuthRepository` when Firebase is not ready |
| Profile | `profileRepositoryProvider` | `FirestoreProfileRepository`, or `UnavailableProfileRepository` |
| Registration/sign-in orchestration | `authServiceProvider` | `AuthService` over the two repositories |
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
/splash          splash       ← shown while the session is unknown
/sign-in         sign in      ← unauthenticated flow
/create-account  create account
/                dashboard    ┐
/rules           rules        ├─ shell branches (bottom navigation, own state)
/history         history      │
/privacy         privacy      ┘
/profile         profile      ← pushed above the shell
/pairing                      ← reserved for the connection phase
```

The authentication guard lives in `app/router/auth_redirect.dart` as a pure
function, so every case is a unit test rather than a manual click-through: see
`AUTHENTICATION_ARCHITECTURE.md` §8.

- Route names and paths live in `AppRoutes` (`app/router/app_routes.dart`); no
  widget uses a string literal path.
- Authentication-aware navigation is wired through `appRouterProvider`, which
  passes the guard and a `refreshListenable` to `createAppRouter()`. The router is
  built inside a provider so it can read authentication state directly, and tests
  exercise the same router the app ships.
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

| Concern | Client | Security Rules (the only authority) |
| --- | --- | --- |
| Observation (battery, charging, network, location) | ✅ collects | — |
| Reading own profile, pair, partner's shared state | reads, gated by rules | — |
| **Authorization** (pair membership, category sharing, consent) | displays only | ✅ enforced on every request |
| Pair activation (`pending → active`) | requests the transition | ✅ **only if both members' consent documents are granted** |
| Issuing/redeeming a pairing code | generates (CSPRNG) and redeems | ✅ length, expiry, single-use, `list` denied |
| Writing notifications | writes **only into its own** collection | ✅ `isSelf(uid)` on every write |
| Interpreting state (rules) | ✅ evaluates locally | — (no server exists) |

There is **no custom server**: the architecture is designed for Firebase Spark.
Firebase client configuration is present, but production intent is unconfirmed.
There is no Cloud Functions project and no Admin SDK
([ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md)). Every former
server responsibility is instead *verified* by the rules — see
`SPARK_ONLY_ARCHITECTURE.md`.

The consequence worth stating plainly: no operation is authorized by the client.
Activation is gated on facts the client cannot forge (each consent document can
only be written by its own subject), so a modified client still cannot join a
pair, read a paused/revoked pair, or widen its own sharing. The rules are tested
against the emulator (70 scenarios, `FIREBASE_SECURITY.md` §7).

### Phase 4 snapshot gaps (later implementation phases)

The Phase 4 snapshot had not yet implemented pairing/consent workflow, device
monitoring, location tracking, or rule management UI. Later phases added the
current app features; remote FCM registration/sending remains intentionally
unimplemented. This document is retained as the earlier architecture baseline.

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
| Auth state model | `test/unit/auth_state_test.dart`, `auth_input_validation_test.dart` | six states; every input rule; client↔rules parity |
| Registration/sign-in | `test/unit/auth_service_test.dart` | three outcomes, partial failure, idempotent retry |
| Auth state machine | `test/unit/auth_controller_test.dart` | transitions, restoration, revocation, outage, sign-out, log hygiene |
| Route guard | `test/unit/auth_redirect_test.dart` | every (state × location) cell |
| Authentication screens | `test/widget/sign_in_screen_test.dart`, `create_account_screen_test.dart` | validation, in-flight, classified failures, unavailable accounts |
| Profile screen | `test/widget/profile_screen_test.dart` | loading, failure, missing profile, create/edit, sign-out |
| Auth routing lifecycle | `test/widget/auth_routing_test.dart` | protection, first frame, full lifecycle, restart |
| DI seams | `test/widget/profile_screen_test.dart` | `ProfileRepository` replaced by a fake |
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
only in `core/firebase/` and feature `data/` layers) recorded in ADR-007.

Phase 4 replaced the Phase 1/2 auth placeholders and made three changes, all
recorded in ADR-008:

| Change | Reason |
| --- | --- |
| `AuthRepository` is identity-only; profile access moved to a new `ProfileRepository` | The old contract returned an `AppUser` whenever an identity existed, which forced fabricating a profile (FR-048) |
| `AppUser` dropped `homeLocation`/`notificationPreference`, which became `UserPreferences` | Phase 3's rules keep those fields owner-only in a separate subdocument, so the model now matches the stored schema |
| `UnauthenticatedAuthRepository` → `UnavailableAuthRepository` (plus its profile twin) | "No account service in this build" is a different fact from "nobody is signed in" |

`createAppRouter` also gained a `refreshListenable`, and `KamApp` now reads
`appRouterProvider` instead of building a router itself. Overall, Phase 4 added
behavior rather than restructuring: no Phase 1–3 domain model changed meaning, and
all earlier tests still pass.

---

## 18. Future extensibility

- **New metrics** (NFR-040): add a `DeviceMetric`, a field on `DeviceState`, a
  capability entry, a collector. No rule-engine or UI redesign.
- **New screens**: add a `GoRoute` (and a branch if it is a primary destination).
- **Authentication**: implement `AuthRepository`, add the `redirect` guard, add
  sign-in/pairing routes already reserved in `AppRoutes`.
- **New platform**: `DevicePlatform.unknown` plus explicit capability states mean
  a new platform degrades to "unsupported" instead of misreporting.
- **Rule evaluation is local by design**: rule definitions are data, and
  `RuleEvaluator` is a pure function of (rule, device state, clock), so the
  evaluator can be extended or moved without changing what a rule *is*. Under
  Spark there is no server-side alternative to move it to.

---

## 19. Explicit non-goals so far

No pairing, device monitoring, location tracking, notification delivery or event
history has been implemented, and no FCM registration exists. There is no Cloud
Functions project — and, since the Spark migration, there never will be one
([ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md)).

What exists is the structure those features plug into: bootstrap, DI seams, routing
shell, result/error handling, platform abstraction, shared UI, logging, the tests
that hold the boundaries, a secure Firestore foundation with enforced pair-scoped
authorization (Phase 3), and user identity with an ownership-enforced profile
(Phase 4).

---

## 20. Authentication and profile (Phase 4)

Full detail: `AUTHENTICATION_ARCHITECTURE.md` and `USER_PROFILE_MODEL.md`.

- **Identity ≠ profile.** `AuthIdentity` comes from Firebase Authentication and
  always exists while signed in; `AppUser` is the `users/{uid}` document and may be
  missing. A missing profile is a first-class state (`Success(null)` → *empty*
  presentation), never a synthesised user (FR-048, NFR-006). ADR-008.
- **`AuthState`** is sealed with six cases (initializing, unauthenticated,
  authenticating, authenticated, signing out, error). The controller mirrors the
  provider's identity stream, so session restoration needs no separate startup
  code; operations also apply their own outcome so the UI never waits on stream
  timing.
- **A guarded router.** `AuthRedirect.resolve` is a pure function; the guard denies
  by default (only sign-in and create-account are reachable without a session) and
  never shows data routes while the session is unknown.
- **Registration** reports three outcomes (`RegistrationComplete`,
  `RegistrationRejected`, `RegistrationProfilePending`). A failed profile write is
  never reported as success and never duplicates a profile, because
  `createProfile` is idempotent.
- **Firebase stays out of the UI.** Feature `data/` layers hold the SDK; the DI
  composition reads raw handles from `core/firebase/firebase_providers.dart` so
  even the provider wiring imports no Firebase package. The architecture test
  enforces it.
