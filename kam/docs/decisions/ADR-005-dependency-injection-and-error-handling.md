# ADR-005 — Dependency injection via Riverpod, and the Result / AppFailure split

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 2

## Context

Phase 2 had to make it possible to introduce Firebase and native device
capabilities later **without coupling the UI to them** (Phase 2 constraints 2 and
3), while remaining testable (NFR-018) and understandable to a small team
(constraint 8). It also had to replace scattered `try/catch` handling with one
consistent error strategy (Task 8, NFR-014) that never leaks backend internals and
never converts a failure into a fabricated device state.

Phase 1 already used Riverpod for state management (ADR-001) and had an
`AppException` hierarchy in `core/errors/`.

## Decision

### 1. Riverpod is the only dependency-injection mechanism

No `get_it`, no service locator, no custom container. External dependencies are
exposed as providers so they can be overridden:

- `appConfigProvider` (must be overridden; throws if it is not),
- `clockProvider`, `loggerProvider`, `platformInfoProvider`,
- `authRepositoryProvider`, `deviceStateSourceProvider`.

This is the *same* mechanism as state management, so there is one concept to
learn rather than two.

### 2. Two error types with different jobs

| Type | Job | Example |
| --- | --- | --- |
| `AppException` (sealed) | What low-level/plugin/SDK code **throws** | `PermissionException`, `RemoteServiceException` |
| `AppFailure` (sealed) | What application code **returns**, already classified and user-safe | `PermissionFailure`, `UnexpectedFailure` |
| `Result<T>` = `Success<T>` \| `Failure<T>` | Repository/source return type | — |

`Result.guard(...)` / `guardSync(...)` convert thrown errors into classified
failures, so `try { } catch (_) { }` is unnecessary at boundaries.
`AppFailure.fromException` maps known exception kinds to failure kinds and maps
everything else to `UnexpectedFailure` with a **generic** message, keeping the
original error in `cause` for logging only.

`sealed` is deliberate: a new failure category becomes a compile-time error until
every switch handles it.

### 3. UI never branches on exception types

The UI converts `AsyncValue<Result<T>>` into a `DataPresentation` via
`PresentationMapping` and renders it with `DataStateView`. Error *classification*
stays out of widgets.

## Consequences

Positive:

- Swapping `UnauthenticatedAuthRepository` → Firebase Auth, or
  `UnavailableDeviceStateSource` → native collectors, is a provider override; no
  UI change and no new abstraction layer.
- Tests inject fakes (`FakeAuthRepository`, `FakeDeviceStateSource`) and a
  `FixedClock`, so no Firebase, network or device is required.
- Errors are consistently classified, logged with their cause, and never shown as
  internals to a user.
- The architecture test in `test/architecture/domain_purity_test.dart` can assert
  that no application file imports a Firebase SDK, which keeps the boundary real
  rather than aspirational.

Negative / accepted trade-offs:

- The `AppException` → `AppFailure` → `DataPresentation` chain is three concepts.
  This is justified by the number of distinct states the SRS requires (unknown,
  unsupported, unavailable, paused, stale, failed, empty) — collapsing them would
  lose information the UI is required to show.
- A provider that must be overridden will throw at runtime if bootstrap is
  bypassed. This is intentional (loud failure over a silent wrong default) and is
  covered by tests using the `pumpTestApp` helper.

## Alternatives considered

- **`get_it` / service locator.** Rejected: a second DI mechanism alongside
  Riverpod, and it resolves dependencies without a visible scope, which makes test
  isolation harder.
- **Passing repositories through widget constructors.** Rejected: it pushes
  dependency plumbing through every widget layer and couples UI shape to
  dependency wiring.
- **One error type (`AppFailure` everywhere, thrown and returned).** Rejected:
  it forces every call site to wrap external calls and blurs the distinction
  between "this can fail as a normal outcome" and "something threw".
- **Exceptions only (current Phase 1 state).** Rejected: encourages silent
  `catch (_)` handling and loses exhaustiveness.
