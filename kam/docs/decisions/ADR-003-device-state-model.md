# ADR-003 — Device-state representation, freshness, and facts vs interpretations

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 1

## Context

The SRS's central product rule is that the application must distinguish
**observed device information** from **interpretations produced by user-defined
rules** (SRS 1.4, 1.5, FR-030, NFR-023, NFR-041), must never present an
unavailable metric as a value (FR-048, FR-068), and must never present stale data
as current (FR-061, NFR-007, NFR-025). It also forbids claiming a device is
powered off (FR-015, FR-070) and requires that a user-defined percentage never be
described as a measured probability (FR-030).

These are modelling decisions, not UI decisions. If they are left to the UI, they
will eventually be violated.

## Decision

1. **Every metric is a `MetricValue<T>`** carrying:
   - `value`, `observedAt` (UTC), `source`, optional `accuracyNote`,
   - `origin` ∈ { `observed`, `derived`, `interpretation` },
   - `availability` ∈ { `available`, `unknown`, `unsupported`, `unavailable`, `paused` },
   - a `FreshnessPolicy`.

   Non-available states are first-class factory constructors
   (`MetricValue.unknown()`, `.unsupported()`, `.unavailable()`, `.paused()`),
   so "we don't know" is as easy to express as a value.

2. **Provenance is part of the type system.** `ValueOrigin.interpretation` and
   `MetricValue.isInterpretation` mean presentation code cannot silently upgrade
   an interpretation into a fact.

3. **Interpretations are a separate domain model.** `Interpretation` carries the
   message, the user-configured `probabilityPercent`, the `basis` (observed facts
   it rests on, satisfying NFR-022), and `isObjectiveFact => false`.
   `RuleAction.displayProbability` asserts that a percentage is present, and the
   field is documented as *user-defined*, never ML-derived.

4. **Freshness is computed from an injected `Clock`.**
   `FreshnessPolicy(freshFor, recentFor)` classifies a value as fresh / recent /
   stale / unknown. Policies are per-metric because metrics age at different
   rates. A future timestamp (clock skew) is treated as fresh, not stale.

5. **No "powered off" concept exists.** Availability is a reachability
   classification (`active`, `recentlySeen`, `offline`, `unknown`) accompanied by
   a last-seen timestamp. Offline is an observation about reachability, never a
   claim about the person or the power state.

6. **Location carries an explicit accuracy field** and its own freshness, so an
   approximate or stale fix is never rendered as an exact position (FR-020,
   FR-023, FR-025).

7. **Revocation keeps provenance but drops the live value.** `asUnavailable()`
   retains the last value and timestamp for audit while marking the metric
   unavailable, so the UI reports "Location unavailable" rather than a stale fix
   (FR-056, NFR-037).

## Consequences

Positive:

- The two invariants are enforced structurally and are already covered by tests
  (`test/unit/metric_value_test.dart`, `freshness_test.dart`, `rule_test.dart`).
- Collectors in Phase 4+ have one obvious return type and cannot "forget" to
  declare availability or a timestamp.
- Server and client can share the same conceptual model.

Negative / accepted trade-offs:

- `MetricValue<T>` is more verbose than a bare `int?`. This is the point: the
  extra type states carry meaning the UI is required to show.
- Generic `MetricValue<T>` prevents wholesale equality; individual fields are
  compared in tests as needed. Value equality can be added later if required.
- Freshness thresholds are policy defaults, not yet tuned to real-world update
  cadences; Phase 4 should validate `FreshnessPolicy.standard` against observed
  collection intervals.

## Alternatives considered

- **Plain nullable fields (`int? battery`).** Rejected: cannot express
  unsupported vs unavailable vs unknown, and loses timestamps/provenance.
- **One big `DeviceState` JSON map.** Rejected: no type safety and no place to
  attach provenance.
- **A confidence/ML probability field on metrics.** Rejected for now: no ML model
  exists, and SRS FR-030 forbids implying one. User-configured percentages live
  on `RuleAction` / `Interpretation`, explicitly labelled as user-defined.
