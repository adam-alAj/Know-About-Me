# Rule Evaluation & Interpretation Messages (Phase 15)

## 1. Purpose and boundaries

Phase 15 makes the rule system useful. It connects the three things Phase 13 and
Phase 14 built — the Rule Engine, the canonical rule model and the rule builder —
to the authorized partner state that Phase 3–12 already synchronize, and turns
the result into something a person can read.

```text
Authorized partner state   (Phase 11 stream, already authorized by Firestore Rules)
          ↓
One state snapshot         (PartnerStateAdapter)
          ↓
Enabled rules only         (RulesController, filtered before the engine)
          ↓
Rule Engine                (Phase 13 RuleEvaluator — unchanged)
          ↓
RuleEvaluationResult       (Phase 13)
          ↓
Interpretation builder     (user wording + observed facts + freshness)
          ↓
InterpretationResult       (Phase 15)
          ↓
Dashboard section          ("What your rules say")
          ↓
Phase 16 notification planner (reads isNewMatch / transition / versions)
```

The phase adds **no** new evaluation semantics. The Rule Engine still decides
whether a condition matched; Phase 15 decides only what that match *means to the
user* and how to say it honestly.

Out of scope, and intentionally untouched: push notifications and FCM, local
notification delivery and scheduling, notification permissions, background
workers, Cloud Functions, Cloud Run, Pub/Sub, Cloud Scheduler, server-side
evaluation, LLM/AI-generated interpretations, scientific probability modelling
and behavioural inference. There is no persistence of evaluation results in this
phase (see §17).

## 2. Architecture

| Layer | Artifact | Responsibility |
| --- | --- | --- |
| Domain | `partner_state_adapter.dart` | Authorized partner state → normalized `DeviceStateSnapshot`; the single place wire state becomes evaluation input |
| Domain | `rule_evaluation_service.dart` | The pure evaluation cycle: enabled filtering, one snapshot, engine invocation, transition classification |
| Domain | `interpretation_builder.dart` | Engine result → user meaning: output kind, user wording, observed facts, freshness, calm explanation |
| Domain | `models/interpretation_result.dart` | `InterpretationResult`, `ObservedFact`, `RuleTransition` |
| Domain | `rule_reevaluation_scheduler.dart` | When a further evaluation is genuinely needed because time passed |
| Presentation | `providers/rule_evaluation_providers.dart` | `ruleEvaluationProvider` (state) + `RuleEvaluationController` (transitions, bounded timer, revocation) |
| Presentation | `widgets/rule_interpretation_card.dart` | `RuleInterpretationCard`, `ObservedFactsSection`, `InterpretationProbability` |
| Presentation | `widgets/interpretation_type_badge.dart` | `InterpretationTypeBadge` |
| Presentation | `widgets/rule_interpretations_section.dart` | Dashboard section with loading / waiting / empty / error / results states |

Nothing above the domain layer decides a match, and nothing in the domain layer
touches a widget, a platform API, Firestore, a model or a notification.

`test/architecture/domain_purity_test.dart` still holds: Firebase is imported
**only** in `lib/core/firebase/` and `lib/features/*/data/`. Phase 15 adds no
Firebase import at all.

## 3. Evaluation lifecycle

1. `ruleEvaluationProvider` watches `rulesControllerProvider` and
   `partnerDeviceStateProvider`.
2. While either is loading the section shows a labelled wait — no evaluation
   runs against half-arrived input.
3. If the rules could not be read, the section reports that plainly and shows no
   interpretations.
4. If there is no authorized partner state, the controller stops evaluating and
   reports "nothing to interpret yet" (§15).
5. Otherwise the controller asks `RuleEvaluationService` for one cycle, stores
   the outcome per rule, and arms at most one bounded timer (§13).
6. The section renders the cycle's `displayable` list.

A cycle re-runs whenever the rules change, the partner state changes, the clock's
scheduled threshold arrives, or the user pulls to refresh. It never runs on a
widget rebuild.

## 4. Enabled-rule filtering

`RuleEvaluationService.evaluate` filters `rule.enabled` **before** the engine is
called, so a disabled rule cannot produce an active interpretation even if a
future engine change stopped reporting `disabled`. Disabled rules remain stored
and are listed by Phase 14; they are simply not evaluated. Nothing is deleted and
nothing is silently enabled.

`RuleEvaluator` independently returns `RuleEvaluationOutcome.disabled` for a
disabled rule, so the two layers agree rather than relying on each other.

## 5. State snapshot model

`PartnerStateAdapter.adapt(RemoteDeviceState)` produces the normalized
`DeviceStateSnapshot` the engine expects. It is the only conversion point, and it
is deliberately lossy in one direction only: it may refuse a value, never invent
one.

| Partner field | Snapshot field | Notes |
| --- | --- | --- |
| `batteryPercentage` | `battery.percentage` | Rejected outside 0–100 |
| `chargingState` (`charging`/`discharging`) | `battery.chargingState` | Normalized to the rule vocabulary (`discharging` → `notCharging`) |
| `chargingDurationSeconds` | `battery.chargingDuration` | Stamped with the *report* time, not the session start (see below) |
| — | `battery.chargingSource` | `unsupported`: charger type is not synchronized |
| `networkState` | `network.status` | — |
| — | `network.connectivity`, `network.internet` | `unknown`: not synchronized |
| `lastOnlineAt`, `networkState: offline` | `network.offlineDuration` | Derived, measured to the published observation time (§10) |
| `screenState`, `activityState` | `activity.*` | `unsupported` markers survive unchanged |
| `deviceAvailability`, `lastOnlineAt` | `availability` | Evidence-based; never a power claim |
| `latitude`/`longitude`/`accuracyMeters`/`approximate` | `location.location`, `location.lastKnownLocation` | Coordinates are only ever carried, never derived |
| `distanceFromHomeKm` | `location.distanceFromHome` | Converted to metres for the engine's contract |
| `homePresence` | `location.presence` | — |
| — | `location.permission`, `serviceState` | `unknown`: the partner's permission is not synchronized |

Two details matter enough to state explicitly:

- **Charging duration is stamped with when the partner reported it.** The wire
  format timestamps the value with the charging *session start*. Using that as the
  observation time would make every long charging session look stale to the
  engine's freshness policy, so a "charging for four hours" rule could never
  fire. The session start is preserved on `BatteryState.chargingStartedAt`, which
  is what the threshold planner reads.
- **Enum fields without a wire timestamp fall back to the document's observation
  time.** Otherwise the engine would see "no observation timestamp" and report
  *unknown* for a value the partner plainly published.

An absent metric becomes `unavailable`, which the engine reports as
`insufficientData` — never as `notMatched`.

## 6. Rule Engine integration

The engine is used exactly as Phase 13 shipped it:
`RuleEvaluator.evaluateAllSnapshot(rules:, snapshot:, nowUtc:)`, with the default
`allowStaleData: false` so a per-rule opt-in stays meaningful. Phase 15 adds no
field to `Rule`, `RuleCondition`, `RuleAction` or `RuleEvaluationResult`.

`RuleEvaluationCycle` wraps the engine's results and adds only:

- the previous/next outcome per rule (for transitions);
- the shared snapshot and evaluation time;
- `active` / `unclear` / `displayable` views over the results.

## 7. Interpretation model

`InterpretationResult` **wraps** the engine's `RuleEvaluationResult` rather than
restating it, so the engine remains the single source of truth for the outcome,
the rule version, the matched conditions and the stale inputs.

| Field | Meaning |
| --- | --- |
| `rule` | The canonical rule that produced this result |
| `evaluation` | The authoritative Phase 13 evaluation |
| `type` | `RuleOutputKind` (`status`, `message`, `probability`) read from the rule's action |
| `transition` | How the match state changed since the previous cycle |
| `title` | The user's own interpretation wording, verbatim |
| `userDefinedProbability` | The user's own configured percentage, 0–100, or null |
| `facts` | The observed facts the engine recorded as the interpretation's basis |
| `freshness` | How current the evidence is |
| `observationTime` | When the *evidence* was observed (not when we read it) |
| `explanation` | A calm reason when the rule could not be decided |

Convenience getters (`isMatched`, `isIndeterminate`, `isNotMatched`,
`isNewMatch`, `isCoolingDown`, `isBasedOnStaleData`, `hasUserDefinedProbability`,
`engineMessage`) exist so the UI and Phase 16 never re-derive those conditions.

## 8. Fact vs interpretation

The three concepts are kept in separate fields and are never composed into a
sentence the app wrote:

```text
FACT          Charging duration: 4h 10m          facts[].description
RULE          Charging duration is at least 4 hours   RuleDescription.conditions(rule)
INTERPRETATION  Possible sleep period             title
                User-defined probability: 70%     userDefinedProbability
```

How false certainty is prevented, structurally:

1. The engine, never a widget, decides the match.
2. Fact text comes from the engine's own `InterpretationBasis.description`, so the
   wording cannot drift between evaluation and display.
3. Condition text is rendered from the persisted rule by Phase 14's helpers, so it
   cannot drift from what was saved.
4. The user's wording is introduced by the literal phrase **"Based on your rule"**
   and is never reworded, expanded or concluded from.
5. A percentage is always printed as **"User-defined probability: N%"**, never as
   "probability that …".
6. `explanation` never contains an engine note, metric name, error code, rule id,
   Firestore path or device identifier.
7. Nothing in the evaluation layer emits a sentence about a person. "They are
   asleep", "the phone is turned off" and "definitely" cannot be produced because
   no code path composes them.
8. There is no `phonePoweredOff` state anywhere in the model (Phase 8/9); the
   adapter has no way to express one.

Tests assert the absence directly (`rule_evaluation_service_test`,
`rule_interpretation_card_test`, `rule_evaluation_flow_test` all search the
rendered output for forbidden phrasings).

## 9. User-defined probability semantics

- Source: `RuleAction.probabilityPercent` on a `displayProbability` action.
- Range: 0–100, enforced at construction (assert), at `Rule.validate()`
  (`invalid_probability` → engine outcome `error`) and by the Phase 14 builder.
  0 and 100 are valid; −1 and 101 cannot be authored.
- Presentation: the literal label `User-defined probability: N%`, with a semantic
  label that adds "This value was set by you, not measured."
- The engine's own rendered sentence ("There is a user-defined N% possibility
  that …") is retained on `engineMessage` for the notification layer, but the card
  shows the user's wording plus the labelled percentage instead.
- The model records the type as `InterpretationProbabilityType.userDefined`, and
  `Interpretation.isObjectiveFact` is permanently `false`.

## 10. Unknown / stale / unsupported handling

The interpretation layer never converts an indeterminate outcome into a match. It
mirrors the engine's outcome and adds a calm sentence:

| Outcome | UI |
| --- | --- |
| `unknown` | "Some of the information this rule needs is not available yet." |
| `staleData` | "This rule is based on information that is no longer current." |
| `unsupported` | "This device cannot report some of the information this rule needs." |
| `permissionDenied` | "Sharing for some of the information this rule needs is turned off." |
| `insufficientData` | "Some of the information this rule needs has not been shared." |
| `error` | "This rule could not be checked." |
| `notMatched` | Not shown at all — it adds noise without adding information |

An indeterminate result is *not* presented as an application failure. The section
distinguishes "the rules could not be read" (a real failure, reported) from "no
rule applies right now" (a successful check with an empty result) from "nothing
to interpret yet" (no authorized state).

Two staleness rules:

- If the engine flagged or blocked a stale input (`staleInputMetrics`,
  `staleData`), the result is `DataFreshness.stale` **even when the caller
  supplies a fresher value**. The engine is authoritative.
- If a rule opts into stale input (`Rule.allowStaleData`), the match is reported
  *and* labelled as no longer current; it is never quietly presented as current.

Location freshness uses `FreshnessPolicy.location` (5 min / 30 min) through the
engine, so a fix older than half an hour cannot support an "away from home"
interpretation by default.

## 11. Multiple matching rules

Every enabled rule is evaluated against the same snapshot and every satisfied rule
keeps its own result. There is no scoring, no precedence and no "winning rule":
Phase 13's `RuleAction` has no priority field, so inventing an ordering would be
inventing semantics. SRS FR-038 (rule precedence) is therefore still recorded as
planned, and the UI shows all matches.

Presentation order is deterministic: matches first, then the undecided rules, each
group sorted by rule name (case-insensitive, rule id as a stable tiebreak).

## 12. Transition handling and duplicate evaluation

`RuleTransition` captures the change between two cycles:

```text
becameMatched      stayedMatched      becameNotMatched     stayedNotMatched
becameIndeterminate                   stayedIndeterminate
```

Rules:

- `isNewMatch` is true **only** for `becameMatched`. This is the single flag Phase
  16 should use to decide whether to alert.
- Repeated state updates while a condition keeps holding produce `stayedMatched`.
  Identical state evaluated twice never produces two "new match" events.
- A rule that starts inside its cooldown is `stayedMatched`, not `becameMatched`:
  the cooldown exists precisely because it already matched, so it must not alert.
- Losing the data a rule needs is `becameIndeterminate`, never
  `becameNotMatched`. "We cannot tell" is not "it stopped being true".
- A rule that was never false and is still false is `stayedNotMatched`, not a
  change.

Transitions are held in memory only, keyed by rule id, and are cleared when the
authorized partner state disappears.

## 13. Cooldown / re-trigger integration

Cooldown is Phase 13's, unchanged: `Rule.isCoolingDownAt(now)` compares
`lastTriggeredAt` with `Rule.cooldown`. The engine reports
`RuleEvaluationOutcome.coolingDown`, which still carries the interpretation (so the
user can see what their rule means) but has `shouldNotify == false`.

Phase 15 surfaces that as `InterpretationResult.isCoolingDown` and as an
`isNewMatch == false` transition. It introduces no second trigger system and
writes no `lastTriggeredAt`; that write belongs to the delivery layer.

## 14. Cost considerations

- Evaluation is entirely local. It reads no Firestore data: the partner state is
  the value the Phase 11 stream is already holding.
- One cycle evaluates all enabled rules against one snapshot; there is no read or
  query per rule.
- Phase 15 writes **nothing** to Firestore. A state update with ten matching rules
  produces zero writes.
- The timer in §13 is bounded and only exists while a time-dependent rule is
  enabled.

## 15. Authorization boundary and pair revocation

Only state the signed-in user is already authorized to read is evaluated. The
evaluation layer never queries partner data itself: it consumes
`partnerDeviceStateProvider`, whose value comes from the Firestore query that the
Security Rules already police. Client-side authorization is a convenience, not the
boundary — Firestore Security Rules remain the enforcement point.

When the pair is disconnected, revoked or expired, `partnerDeviceStateProvider`
resolves to `null`. The controller then:

- stops evaluating;
- cancels any pending timer;
- clears the previous outcomes, so a later reconnection cannot look like a
  transition that never happened;
- reports "Nothing to interpret yet" instead of stale partner interpretations.

Existing interpretations are not retained: Phase 15 keeps them in widget state
only, so the dashboard simply stops showing them (Step 25 of the phase brief).
The dashboard also stops rendering the section entirely when no active connection
exists.

## 16. Rule changes, deleted rules and versions

- **Edited rule (FR-035):** the rule id is stable and `version` increments. The
  controller re-evaluates as soon as the rules change, so a new cycle uses the new
  definition and the new threshold. `InterpretationResult.ruleVersion` records
  which version ran.
- **Deleted rule (FR-036):** the rule is absent from the list, so it is no longer
  evaluated and no new interpretation can appear. Phase 15 fabricates no
  replacement and keeps no history to fall back on (history is Phase 17).
- **Disabled rule (FR-034):** filtered before the engine, so it produces no
  result at all (§4).

## 17. Time-dependent evaluation

A rule such as "charging duration is at least 4 hours" becomes true at a known
instant even if no device event arrives exactly then.

`RuleReevaluationScheduler.nextDelay` computes the single earliest crossing across
all enabled rules:

- only conditions that are *definitely* matched or not matched are considered — a
  rule waiting for data is waiting for the partner, not the clock;
- only metrics whose value is exactly `now − anchor` can be planned
  (`chargingDuration`, `lastOnlineDuration`, `lastActivityDuration`,
  `locationAge`, `timeSinceLastAvailability`). The anchor comes from the engine's
  recorded input observation times, except charging duration, which the planner
  reads from `battery.chargingStartedAt` on the snapshot;
- the delay is `threshold − elapsed`, plus one second for the strict operators;
- the result is clamped to between one second and fifteen minutes.

The controller arms **one** timer for that delay. When it fires, it re-evaluates
locally (no I/O) and re-plans. The fifteen-minute cap doubles as a freshness
re-check: a result can legitimately turn `stale` purely with age, and nothing else
in the app needs to run more often. There is no second-by-second polling, and no
timer at all when no time-dependent rule is enabled.

Documented limitation: an `offlineDuration` rule is not planned, because its value
is measured to the moment the partner published it rather than to `now`. Such a
rule still re-evaluates on every incoming state update, which is exactly when the
partner can extend the figure.

## 18. UI presentation

`RuleInterpretationsSection` is rendered on the Partner Reassurance Dashboard,
directly beneath the state panels it interprets, inside the active-connection
branch:

```text
What your rules say
  ┌──────────────────────────────────────────────┐
  │ Long Charging                                │
  │ [User-defined probability]                   │
  │ Based on your rule                           │
  │ Possible sleep period                        │
  │ [User-defined probability: 70%]              │
  │ Why this rule matched                        │
  │   • Charging duration: 4h 10m                │
  │   Rule condition: Charging duration is at    │
  │   least 4 hours                              │
  │ Updated just now                             │
  │ Last checked 9/28/2026, 2:00 PM              │
  └──────────────────────────────────────────────┘
```

Tone (STEP 18): neutral surfaces, outline/secondary colours, no error colour for
an ordinary match, no "ALERT"/"WARNING", no exclamation. The `AppInlineMessage`
tone used for an undecided result is `info`, not `warning`.

Accessibility (STEP 41):

- every badge and chip pairs an icon with a word, and each carries a semantic
  label, so meaning never depends on colour;
- the probability carries a semantic label that states it was set by the user and
  not measured;
- freshness is text plus icon, never colour alone;
- the loading state is a labelled live region;
- the button-free section keeps full-width touch targets.

Responsiveness (STEP 42): the rule name ellipsizes after two lines; the type badge
sits on its own line and its label wraps then ellipsizes; the probability chip
shrinks and wraps; fact rows put the value in an `Expanded`. Tests cover a long
name, a long interpretation and a 360 px surface.

## 19. Deferred: notifications (Phase 16)

Phase 15 exposes exactly what a local notification planner needs and nothing more:

| Need | Where |
| --- | --- |
| Which rule matched | `InterpretationResult.rule`, `ruleId` |
| Which definition ran | `ruleVersion` |
| Whether this is a new event | `isNewMatch` (`RuleTransition.becameMatched`) |
| Whether it is inside cooldown | `isCoolingDown`, `evaluation.outcome` |
| The message to deliver | `engineMessage` (engine-rendered) and `title` |
| The user-defined probability | `userDefinedProbability` |
| Whether the basis is stale | `isBasedOnStaleData`, `evaluation.staleInputMetrics` |
| When it was decided | `evaluatedAt` |
| When the evidence was observed | `observationTime`, `evaluation.inputObservationTimes` |
| Whether the pair is even active | `RuleEvaluationState.hasPartnerState` |

`RuleNotificationPlanner` (Phase 13, at
`lib/features/notifications/domain/rule_notification_planner.dart`) already
consumes the wrapped `RuleEvaluationResult`, so Phase 16 needs no change to the
engine. Delivery, permission handling, scheduling and the `lastTriggeredAt` write
are Phase 16's.

## 20. Deferred: evaluation history (Phase 17)

Phase 15 defines the shape a future event record would carry
(`ruleId`, `ruleVersion`, `status`, `transition`, `interpretation`,
`evaluationId`, `evaluatedAt`, observation times) but persists nothing. In
particular there is no Firestore write per state update: one state update with ten
rules produces zero writes, which is what the Spark-only cost constraint requires.
A repository abstraction and change-aware persistence belong to Phase 17.
`pairs/{pairId}/interpretations/{id}` already exists in the data model and its
Security Rules already require `isUserDefined: true`, so persistence can be added
later without a rules change.

## 21. Testing

```bash
flutter analyze
flutter test
firebase emulators:exec --only firestore --project demo-kam \
  "node --test firebase/test/firestore.rules.test.js"
```

| Suite | File | Covers |
| --- | --- | --- |
| Adapter | `test/unit/partner_state_adapter_test.dart` | Carrying values unchanged, absent → unavailable, non-available reasons preserved, km → metres, derived offline duration, availability evidence |
| Builder | `test/unit/interpretation_builder_test.dart` | Output kind, user wording, probability labelling and boundaries, explanations, stale forcing, forbidden phrasings |
| Service | `test/unit/rule_evaluation_service_test.dart` | Matched, boundaries, unknown/stale, multiple rules, disabled/deleted, versions, every transition pair, cooldown, groups, no partner state |
| Scheduler | `test/unit/rule_reevaluation_scheduler_test.dart` | Crossing calculation, strict operators, upper bounds, clamping, no-data, documented offline limitation |
| Card | `test/widget/rule_interpretation_card_test.dart` | Facts, probability label, unknown/stale, no unsupported claim, long content |
| Section | `test/widget/rule_interpretations_section_test.dart` | Results, loading, waiting, empty, failed read, disabled rule, narrow surface |
| Flow | `test/widget/rule_evaluation_flow_test.dart` | Rule + authorized partner state → interpretation on the real dashboard; disabled rule; ended pair |

Manual scenarios from the phase brief map to the flow suite: long charging
(matched, 70% labelled, facts visible), offline, unknown location, stale location,
multiple rules, disabled rule, edited rule version, pair revocation.
