# Architecture Decision Records

Decisions made during Phases 1–3. Each ADR records the context, the decision, its
consequences and the alternatives that were rejected.

| ADR | Title | Phase | Status |
| --- | --- | --- | --- |
| [ADR-001](ADR-001-project-architecture.md) | Feature-first layered architecture and Riverpod state management | 1 | Accepted |
| [ADR-002](ADR-002-firebase-boundaries.md) | Firebase responsibility boundaries and deferred integration | 1 | Accepted |
| [ADR-003](ADR-003-device-state-model.md) | Device-state representation, freshness, and facts vs interpretations | 1 | Accepted |
| [ADR-004](ADR-004-configuration-strategy.md) | Configuration and environment strategy | 1 | Accepted |
| [ADR-005](ADR-005-dependency-injection-and-error-handling.md) | Dependency injection via Riverpod, and the `Result` / `AppFailure` split | 2 | Accepted |
| [ADR-006](ADR-006-state-scoping-and-async-presentation.md) | State scoping and the async data-presentation contract | 2 | Accepted |
| [ADR-007](ADR-007-firebase-integration.md) | Firebase integration approach, configuration and boundaries | 3 | Accepted |

Convention: file name `ADR-NNN-kebab-case-title.md`; status is one of Proposed,
Accepted, Deprecated, Superseded.
