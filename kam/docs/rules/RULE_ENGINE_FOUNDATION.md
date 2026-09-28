# Rule Engine Foundation (Phase 13)

## Purpose and boundaries

The rule engine deterministically evaluates user-authored conditions against a
single authorized device-state snapshot. It is a pure Dart domain component: it
does not access widgets, Firebase, Firestore, network services, platform APIs,
notifications, or language models. The caller obtains and authorizes the state
through the existing pairing and sharing flow before calling
`RuleEvaluator.evaluateSnapshot`.

This remains compatible with the Firebase Spark-only architecture. Evaluation
runs on the client, grants no access, and does not write a result or event.
Firestore Security Rules remain the authorization boundary.

## Domain model

`Rule` carries its ID, owner and pair scope, name, enabled state, version,
single-condition compatibility field, optional AND/OR condition group, actions,
cooldown, last-trigger time, stale-input opt-in, and lifecycle timestamps. Call `validate()` before
persisting rules or evaluating untrusted decoded values. Validation reports
structured, non-sensitive issue codes for missing scope, invalid metric/value
combinations, bad thresholds, invalid version/cooldown, and invalid percentage.

Conditions have a closed `RuleMetric` and `RuleOperator` vocabulary. Numeric and
duration thresholds are represented separately from state values. A group is a
small list of conditions combined with `all` (AND) or `any` (OR); nested generic
expression languages are intentionally excluded. Numeric comparisons use
ordinary Dart number comparisons, so `>` excludes the exact boundary and `>=`
includes it.

## Supported metrics and operators

Metrics map to the normalized models from Phases 6–12:

- Battery percentage, charging state, and charging duration.
- Network type, internet availability, online/offline status, offline duration,
  and elapsed time since last online.
- Screen state and elapsed time since last observable activity.
- Device availability and elapsed time since positive availability evidence.
- Location availability, location age, distance from home, and home presence.

Location rules consume derived distance and presence. The engine does not put
coordinates in an interpretation, result, or evaluation fingerprint.

Supported operators are `equalTo`, `notEqualTo`, `greaterThan`,
`greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `isA`, `isNot`, and
`hasRemainedInStateFor`. Validation rejects state values on numeric metrics,
numeric values on state metrics, non-finite or negative thresholds, invalid
battery percentages, and incompatible duration conditions.

## Evaluation semantics

- `matched`: the complete condition or group matched usable observations.
- `notMatched`: available observations definitively disprove the condition.
- `unknown`: an input or observation timestamp is missing or explicitly unknown.
- `staleData`: an input is explicitly stale or beyond its metric freshness
  policy; stale values do not match by default.
- `unsupported`: the required capability is not supported.
- `permissionDenied`: an input is blocked by permission.
- `insufficientData`: an input is unavailable or sharing is paused.
- `error`: validation or a normalized input error prevents safe evaluation.
- `disabled` and `coolingDown`: the rule is disabled or matches during its
  cooldown. A cooling-down match is still a match but does not request a new
  notification.

For AND, a definite false makes the group not matched; otherwise any unknown
input keeps the result indeterminate. For OR, any true condition matches;
otherwise an unknown input keeps the result indeterminate. Unsupported,
permission, stale, and error reasons remain distinct in the result. A caller or
rule may explicitly opt into stale observations; those input metric names remain
marked in `staleInputMetrics`. Legacy
single-condition callers keep their existing `DeviceState` API; new callers
should supply the canonical `DeviceStateSnapshot`.

Each result contains the rule ID and exact rule version, evaluated UTC time,
condition indices, input observation times, status, optional interpretation,
and a deterministic evaluation ID built from the rule version and normalized
condition evidence. Re-evaluating identical inputs yields the same ID; no event
storage or persistent deduplication ledger is added in this phase. `evaluateAll`
and `evaluateAllSnapshot` preserve input order and return every result; rules
have no invented global precedence.

Time is supplied explicitly as UTC `nowUtc`; tests use a fixed time. Durations
are calculated in UTC elapsed time, so local daylight-saving transitions do
not alter comparisons.

## Facts and interpretations

An `Interpretation` is output authored by a rule, separate from observed facts.
Its evidence basis includes metric names, descriptions, and observation times.
It never includes exact location coordinates. A configured percentage is
tagged `userDefined` and is not a statistical confidence, model result, or
scientifically validated probability. No AI/LLM or heuristic inference is used.

## Repository, cooldown, and retrigger foundation

`RuleRepository` defines owner-and-pair-scoped read/save/update/delete
operations for a later persistence implementation. No Firestore rule documents
or listeners are introduced now. The existing `cooldown` and
`lastTriggeredAt` fields provide deterministic `afterCooldown` behavior; the
result's `shouldNotify` is true only for a newly matched, non-cooling-down rule.
Transition-based retrigger state and durable idempotency storage are deferred
until the event/notification phase.

## Validation and testing

Unit tests cover strict/inclusive comparison boundaries, durations, stale and
missing observations, state comparisons, location-derived inputs, cooldowns,
simultaneous rules, AND/OR with partial unknown values, normalized snapshot
inputs, invalid condition combinations, rule versions, observation timestamps,
and repeat-evaluation fingerprints. Clock time is fixed in tests; the evaluator
never calls `DateTime.now()`.

## Deferred work

Phases 14–16 own rule creation/edit/list UI, persistence implementation,
interpretation presentation, event records, notification permissions and
delivery. This phase creates only the domain and evaluation foundation needed
by those layers.
