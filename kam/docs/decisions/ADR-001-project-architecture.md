# ADR-001 — Feature-first layered architecture and Riverpod state management

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 1

## Context

The application must grow from a small foundation to cover authentication,
pairing, device monitoring, location, synchronization, a rule engine,
notifications, history and privacy controls (SRS NFR-017). It must stay
understandable to a small student team (constraint 8), keep domain logic
testable independently (NFR-018), and avoid premature enterprise structure
(constraints: no microservices, no unnecessary abstractions).

The starting repository was an unmodified `flutter create` template: a single
`lib/main.dart` counter app and no structure to preserve.

Two decisions are entangled here: how code is organised, and how state is
managed. They are recorded together because the state-management choice constrains
how features are organised.

## Decision

1. **Organise by feature**, with an optional `domain/` + `data/` +
   `presentation/` split inside each feature, and cross-cutting code in `core/`.
   `domain/` must remain pure Dart (no Flutter, no Firebase, no plugins).
2. **Use Riverpod (`flutter_riverpod`) as the only state-management mechanism.**
   Root providers live in `lib/app/providers.dart` and are overridden at startup
   and in tests.
3. **Do not introduce** use-case interactors, a repository interface per model,
   or code generation. Layers are created only when a feature needs them.

## Consequences

Positive:

- New features are additive: a directory plus its providers.
- Domain models are directly unit-testable; Phase 1 already tests `MetricValue`,
  freshness, rules, pairing, consent and privacy with no device or Firebase.
- Provider overrides give a single, explicit seam for injecting configuration and
  later fakes/stubs (`appConfigProvider`, `clockProvider`).
- Async loading/error/data states are explicit, matching the "unknown /
  unavailable / stale" contract the SRS demands.

Negative / accepted trade-offs:

- Riverpod is a dependency the team must learn; it also changes between major
  versions (Phase 1 pins `flutter_riverpod` 3.x).
- The "pure domain" rule cannot be enforced by the analyzer, so it relies on
  review.

## Alternatives considered

- **`provider` + `ChangeNotifier`.** Simpler conceptually, but requires a
  `BuildContext`, makes test injection of time/config clumsier, and mixes mutable
  state with widgets. Rejected.
- **BLoC.** Strong testability and event modelling, but significantly more
  boilerplate per feature than this project's size justifies. Rejected for now;
  can be revisited per-feature if complexity demands it.
- **No state-management package.** Would push ad-hoc `InheritedWidget`s and
  `setState` across features; rejected as it does not scale to async synced data.
- **Layer-first organisation (`lib/models`, `lib/services`, …).** Becomes a
  navigation problem as features grow and hides feature boundaries. Rejected.
