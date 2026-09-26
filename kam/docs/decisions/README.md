# Architecture Decision Records

Decisions made during Phases 1–4. Each ADR records the context, the decision, its
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
| [ADR-008](ADR-008-identity-profile-separation.md) | Identity vs profile separation, and the partial-registration strategy | 4 | Accepted |
| [ADR-009](ADR-009-spark-only-no-cloud-functions.md) | Spark-only architecture: no Cloud Functions, no billing account | 5 | Accepted — supersedes the Cloud Functions rows of ADR-002 |
| [Requested Spark migration filename](ADR-004-remove-cloud-functions-spark-only.md) | Companion copy of ADR-009 (canonical decision) | 5 | Accepted |

Convention: file name `ADR-NNN-kebab-case-title.md`; status is one of Proposed,
Accepted, Deprecated, Superseded.

Numbering note: the Spark-only migration brief asked for this decision to be
recorded as `ADR-004`. That identifier was already held by
[ADR-004](ADR-004-configuration-strategy.md), and reusing it would have made the
index and every existing cross-reference ambiguous, so the next free number was
used. Existing ADRs were not renumbered.
