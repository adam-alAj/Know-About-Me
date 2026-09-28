# Rule Builder & Rule Management (Phase 14)

## 1. Purpose and boundaries

Phase 14 adds the user-facing half of the rule system on top of the Phase 13
Rule Engine. A user can list their rules, create one, define one or more
conditions, group them with ALL/ANY, define what the rule means when it matches,
optionally attach a user-defined probability, enable or disable it, edit it,
validate it and delete it.

The phase deliberately reuses the canonical Phase 13 models. There is no second
rule representation: the builder keeps a temporary **draft** whose only job is to
survive being edited, and converts it into the canonical `Rule` exactly once,
after validation.

```text
Rule Builder UI
      ↓
Rule Draft            (lib/features/rules/domain/rule_draft.dart)
      ↓
Validation            (RuleDraft.validate + Rule.validate)
      ↓
Canonical Rule Model  (lib/features/rules/domain/models/rule.dart, Phase 13)
      ↓
Rule Repository       (lib/features/rules/domain/repositories/rule_repository.dart)
      ↓
Stored Rule           (users/{uid}/rules/{ruleId})
      ↓
Rule Engine           (Phase 13, unchanged)
```

Out of scope for this phase, and intentionally untouched: notification delivery,
push notifications, local notification scheduling, interpretation history,
AI/LLM-generated rules, server-side evaluation, Cloud Functions and any paid
Google Cloud service. Rules may be stored in Firestore because Firestore is part
of the existing Spark-compatible architecture; authorization remains enforced by
Firestore Security Rules.

## 2. Architecture

| Layer | Artifact | Responsibility |
| --- | --- | --- |
| Domain | `metric_definition.dart` | The closed metric catalogue: value kind, allowed operators, selectable states, unit, platform note |
| Domain | `rule_draft.dart` | Editable draft, domain validation, canonical conversion, duplicate signature |
| Domain | `rule_description.dart` | Pure, human-readable rendering of a rule (list + builder) |
| Domain | `rule_id_generator.dart` | Opaque, path-safe rule document ids |
| Data | `rule_serialization.dart` | Canonical model ↔ Firestore document shape |
| Data | `repositories/firestore_rule_repository.dart` | The real persistence implementation |
| Data | `repositories/in_memory_rule_repository.dart` | Session-only store used by tests and by a build with no account service |
| Presentation | `providers/rule_providers.dart` | Repository selection, active scope, `RulesController` (state + all writes) |
| Presentation | `rules_screen.dart` | List, empty states, enable/disable, delete |
| Presentation | `rule_builder_screen.dart` | Create/edit form |
| Presentation | `widgets/*` | `RuleCard`, `RuleStatusBadge`, `RuleConditionEditor`, `RuleChoiceField`, `RuleValidationMessage` |

The dependency direction is enforced by `test/architecture/domain_purity_test.dart`:
Firebase is imported **only** in `lib/core/firebase/` and `lib/features/*/data/`.
No widget ever reaches Firestore; the screens talk to `RulesController`, which
talks to `RuleRepository`.

## 3. Rule lifecycle

```text
Draft → Validation → Saved (enabled) → evaluated by the Rule Engine
Saved (enabled) → Disabled → Re-enabled
Saved → Edited (draft) → Validation → Updated (version + 1)
Saved → Deleted (confirmed)
```

Rules are never partially saved. The builder validates the whole draft and writes
the whole rule in one operation; a failed validation keeps the user on the
builder with the problems listed, and a failed write leaves the previous state
untouched.

## 4. Rule list screen

`RulesScreen` renders one of four honest states:

| State | What the user sees |
| --- | --- |
| No active connection | "No connection yet" and an explanation; no create action |
| Checking / loading | A labelled spinner |
| Empty (connected) | "No rules yet" with a calm explanation and a Create action |
| Loaded | One `RuleCard` per rule, newest first |

Each card shows the rule name, an enabled/disabled badge, a concise condition
summary ("When …"), the interpretation ("Then …") and, when available, the last
updated time. Internal ids, Firestore paths and device identifiers are never
shown.

Load is explicit and on demand: the list reads once when it opens, and again
after a save or delete (a local state update, not a re-read). There is no
listener per rule and no polling.

## 5. Rule creation flow

One screen, one scroll, four sections — no extra navigation complexity:

1. **Rule name.**
2. **When this is true** — one or more condition cards, an "Add condition"
   button, and an ALL/ANY selector that appears once there is more than one
   condition.
3. **Then interpret it as** — interpretation type (Status / Message /
   User-defined probability), the wording, and the probability field when
   applicable.
4. **Options** — enabled state and the repeat (cooldown) setting, followed by a
   short "Facts and interpretations" note.

Save and Cancel sit at the bottom. Save validates the whole draft in the domain
layer and persists atomically; Cancel discards the draft without writing
anything.

## 6. Editing flow

Opening a rule loads the complete canonical rule into a draft
(`RuleDraft.fromRule`). Nothing is written while the user types. Saving validates
the entire rule again and performs one atomic update, after which:

```text
Rule ID      remains stable
Rule version increments by 1
createdAt    unchanged (server-authoritative, immutable in the Security Rules)
updatedAt    server timestamp
```

The date/time formatting for the list is `DateTimeUtils.formatLocalTimestamp`
(NFR-026: UTC in storage, local only at display).

## 7. Deleting a rule

Deleting is destructive and always confirmed by a dialog that names the rule the
way the user knows it ("Delete \"Long Charging\"?"). No internal id is shown.
After a successful delete the rule leaves the list and the next evaluation sees
it gone. Disabled rules are **not** auto-deleted — only an explicit delete
removes a rule. Deleting a rule does not touch interpretation/event records owned
by later phases; the confirmation says so.

## 8. Validation rules

Validation lives in the domain layer (`RuleDraft.validate`) and is not the only
boundary: the same draft is validated again by the controller before persistence,
and the canonical `Rule.validate()` remains available for stored data.

| Code | Condition |
| --- | --- |
| `missing_name` | Name empty or whitespace only |
| `name_too_long` | Name longer than 120 characters |
| `no_conditions` | No conditions at all |
| `missing_value` | A condition has no value |
| `invalid_numeric_value` | A numeric threshold is not a number |
| `invalid_duration_value` | A duration is negative |
| `battery_out_of_range` | A percentage is outside 0–100 |
| `invalid_state_value` | A state is not in the metric's closed set |
| `invalid_operator` | The operator does not apply to the metric |
| `duplicate_condition` | The same condition appears twice |
| `missing_output` | No interpretation text |
| `output_too_long` | Interpretation text longer than 200 characters |
| `invalid_probability` | Probability missing, non-integer, or outside 0–100 |
| `invalid_cooldown` | Negative repeat interval |

The builder shows a summary block (icon + text, in a live region) and per-field
messages. A rule with any issue cannot be persisted.

### Duplicate handling

`RuleDraft.behaviourSignature` is a deterministic key over the group operator,
the conditions (order-independent, thresholds normalised, so *240 minutes* and
*4 hours* are the same) and the interpretation. Before saving, the controller
rejects a rule whose signature matches a different existing rule. Semantic
equivalence beyond this is deliberately not attempted.

## 9. Supported metrics

Exposed metrics are exactly those the Phase 13 engine can resolve. Each metric
declares how its value is entered:

| Metric | Kind | Unit | Notes |
| --- | --- | --- | --- |
| Battery percentage | percentage | `%` | 0–100 |
| Charging | state | — | Charging / Not charging / Fully charged / Unknown |
| Charging duration | duration | minutes, hours | |
| Connection | state | — | Online / Offline / Unknown |
| Connection type | state | — | Wi-Fi / Mobile data / Ethernet / Bluetooth / VPN / No connection / Unknown |
| Internet access | state | — | Available / Unavailable / Unknown |
| Offline duration | duration | minutes, hours | |
| Time since last online | duration | minutes, hours | |
| Screen | state | — | On / Off / Unknown (platform-dependent) |
| Time since last activity | duration | minutes, hours | platform-dependent |
| Device availability | state | — | Available / Not available / Unknown |
| Time since last confirmed availability | duration | minutes, hours | |
| Distance from home | number | `km` | platform-dependent |
| Home presence | state | — | At home / Near home / Away from home / Unknown |
| Location availability | state | — | Available / Unavailable / Unknown |
| Age of the last location reading | duration | minutes, hours | platform-dependent |

Metrics marked platform-dependent show a short note in the builder explaining
that the rule reports "unknown" rather than guessing when the capability is
absent (FR-048, FR-068).

`test/unit/rule_metric_definition_test.dart` asserts that every `RuleMetric`
has a definition, so the catalogue cannot silently drift behind the engine.

## 10. Supported operators

For percentage, number and duration metrics:

```text
is / is not / is greater than / is at least / is less than / is at most
```

For state metrics:

```text
is / is not
```

The builder only ever offers operators from the selected metric's definition, so
combinations such as *Battery percentage is Wi-Fi* or *Distance from home is
Charging* cannot be assembled. `RuleOperator.hasRemainedInStateFor` is not
offered by the builder: the equivalent user-facing form is an explicit duration
metric ("Charging duration is at least 4 hours").

## 11. Condition grouping

Phase 13 supports a *flat* list of conditions combined with `all` (AND) or `any`
(OR). The builder mirrors that exactly: a top-level ALL/ANY control plus a flat
list of condition cards. Nested groups are not part of the domain model and are
therefore not offered. The control only appears when there is more than one
condition, and a caption spells the semantics out ("The rule matches when every
condition is true.").

## 12. Output / interpretation configuration

The interpretation type maps onto the canonical action:

| Builder output | `RuleActionType` | Stored as |
| --- | --- | --- |
| Status | `displayStatus` | `messageTemplate` |
| Message | `displayMessage` | `messageTemplate` |
| User-defined probability | `displayProbability` | `messageTemplate` + `probabilityPercent` + `isUserDefined: true` |

Notification, event and reassurance-indicator actions exist on the canonical
model but are never produced here; they belong to Phase 16.

## 13. User-defined probability semantics

The probability is the user's own estimate. The UI labels it "User-defined
probability (%)" and states that it is *not* a calculated or verified
probability. The stored action is flagged `isUserDefined: true`, and the
interpretation produced by the engine is always phrased as a *possibility*
("There is a 70% possibility that …"). The application never describes it as a
scientific, statistical or AI-computed value.

## 14. Fact vs interpretation

The builder contains an explicit note:

> Conditions describe device state the app can observe. The interpretation is
> your own wording for what that might mean — it is not a claim about what the
> other person is doing.

The canonical model reinforces this: `Interpretation.isObjectiveFact` is always
`false`. The rule list header repeats the framing ("Interpretations you defined.
They describe a possibility, not a fact about the other person.").

## 15. Enable / disable

`enabled` is a first-class rule field. A rule can be created enabled or disabled
and toggled at any time. Toggling updates only `enabled` and `updatedAt`; it does
not change the definition version and never deletes the rule. Disabling makes the
Rule Engine return `RuleEvaluationOutcome.disabled`, so a disabled rule cannot
contribute to later evaluation flows.

## 16. Versioning

Versioning follows Phase 13 unchanged: the rule id is stable for a rule's whole
life, and `version` increments by one each time the saved definition changes
through the builder (`RuleDraft.nextVersion`). Enable/disable does not bump the
version. `RuleEvaluationResult.ruleVersion` records the exact definition that was
evaluated, so historical evaluation metadata is never silently mutated.

## 17. Repository architecture

```text
Widget → RulesController → RuleRepository → Firestore
```

`RuleRepository` is the Phase 13 domain interface; it is implemented by
`FirestoreRuleRepository` (production) and `InMemoryRuleRepository` (tests, and a
build with no account service). The controller owns all writes; the screens only
construct drafts and call controller methods.

Cost-consciousness (SRS Task 24, NFR-039):

- the list reads once on open with a single equality query (`pairId`), which uses
  Firestore's automatic index — no composite index is required;
- no listener is installed per rule, and no polling;
- editing is local until Save, so there is no write per keystroke and no
  autosave;
- enable/disable and delete update local state after the write resolves rather
  than re-reading the collection.

## 18. Firestore structure

```text
users/{ownerUserId}/rules/{ruleId}
  ownerUserId        string   must equal the path owner
  pairId             string   the active connection the rule describes
  name               string   1–120 characters
  version            int      ≥ 1
  enabled            bool
  allowStaleData     bool     per-rule stale-input opt-in (Phase 13)
  cooldownSeconds    int      ≥ 0
  condition          map      { metric, operator, numericThreshold?, stateValue?, durationSeconds? }
  conditionGroup     map?     { operator: all|any, conditions: [ … ] }
  actions            list     ≤ 8 entries; a probability action carries isUserDefined: true
  lastTriggeredAt    timestamp? written by the evaluation/notification phase
  createdAt          timestamp server timestamp
  updatedAt          timestamp server timestamp
  schemaVersion      int      currently 1
```

Only one condition is stored in `condition` for a single-condition rule; the
group is materialised when there is more than one, matching the Phase 13
compatibility shape. The document id is never stored inside the document.

## 19. Security Rules

`firebase/firestore.rules` keeps rule definitions owner-private and independent
of the client:

- `read` and `delete` require `isSelf(userId)`.
- `create`/`update` require `isSelf(userId)`, `ownerUserId == userId`, a closed
  key set (`keys().hasOnly([...])`), a type- and range-checked value set, a
  well-formed condition, and `updatedAt == request.time`.
- `create` additionally requires `createdAt == request.time`.
- `update` requires `createdAt` to equal the stored creation time, so history
  cannot be rewritten.
- Free-text values are length-bounded (name ≤ 120, actions ≤ 8).

Authorization does not depend on any value the client supplies: owning,
pair-related or identity fields are re-checked against `request.auth.uid` and the
path. The partner never reads rule definitions — only the interpretation a rule
produces, if the owner shares it.

Covered by the emulator tests in `firebase/test/firestore.rules.test.js`
(owner access, cross-user denial, unauthenticated denial, closed field set,
server-authoritative timestamps, immutability of `createdAt`, and partner
isolation).

## 20. Offline behaviour

Firestore's own offline semantics are used; no custom offline layer was added.

- A write that resolves locally is reported as saved (Firestore queues it and
  flushes on reconnect).
- A failed write surfaces the classified `AppFailure.message` in an inline
  message on the builder, and the previous state is left intact.
- Loading failures show a retry action.

The list reflects the local state the controller applied after a successful
write, so an offline save is visible immediately.

## 21. Error handling

| Situation | Presentation |
| --- | --- |
| Validation failure | Inline summary + per-field messages; the rule is not saved |
| Firestore permission denied | "You do not have access to this information." (from `FirebaseErrorMapper`) |
| Session expired | "Your session has expired. Please sign in again." |
| Network unavailable | "Could not reach the service. Check your connection and try again." |
| Malformed stored rule | The document is skipped on read; opening it reports "could not be read and cannot be edited. You can delete it." |
| Authentication expired / revoked | Writes fail with a classified failure; the screen offers no false success |
| Pair revoked / disconnected | Rules remain owner-private but the scope becomes "not connected", so no rule is offered for the missing pair |

Raw exceptions and Firestore internals are never shown; classified, user-safe
messages come from `AppFailure`. Logging records only operation names and failure
categories — never a rule name, condition or owner id.

## 22. Pair / connection lifecycle

Rules describe a partner's device, so the builder requires an active pair
(`ruleScopeProvider`, derived from `partnerScopeProvider`). With no active
connection the Rules screen and builder explain that a connection is needed
instead of offering a rule that could not be saved. Disconnecting, revoking
consent or losing authorization therefore removes the ability to author rules for
that pair; the integration point with the Phase 18 privacy/connection lifecycle
is this scope provider, which is not duplicated here.

## 23. Privacy

Rule configuration is user-owned private data. The UI shows human-readable names
and values only — never an internal id, a Firestore path, a device identifier or
authorization metadata. No analytics or telemetry containing rule content is
produced.

## 24. Accessibility and responsive design

- Enabled/disabled is conveyed by an icon **and** the word "Enabled"/"Disabled",
  never by colour alone.
- Controls carry labels; the switch and badges have semantic labels; validation
  messages render inside a live region.
- Touch targets use standard Material controls; the condition list is a normal
  scrollable list.
- The builder is a single scrolling `ListView` inside a 640 px-wide constraint,
  with no hard-coded heights, so it works on small phones and wider layouts.

## 25. Testing

| Area | File |
| --- | --- |
| Metric catalogue ↔ engine consistency | `test/unit/rule_metric_definition_test.dart` |
| Draft validation, canonical conversion, versioning, duplicates | `test/unit/rule_draft_test.dart` |
| Document encoding/decoding and malformed data | `test/unit/rule_serialization_test.dart` |
| Repository CRUD and scoping | `test/unit/in_memory_rule_repository_test.dart` |
| List, empty states, enable/disable, delete confirmation | `test/widget/rules_screen_test.dart` |
| Create, validation errors, add/remove condition, metric/operator/value, cancel | `test/widget/rule_builder_screen_test.dart` |
| Full lifecycle (create → edit → disable → re-enable → reject → delete) | `test/widget/rule_management_flow_test.dart` |
| Firestore authorization | `firebase/test/firestore.rules.test.js` |

## 26. Deferred to later phases

- **Phase 15** — evaluation orchestration and presenting interpretations: reading
  the partner's authorized device state, running `RuleEvaluator`, and displaying
  `RuleEvaluationResult` with its outcome vocabulary.
- **Phase 16** — notifications: permissions, local delivery, the notification
  centre and `lastTriggeredAt` bookkeeping.
- Transition-based retrigger (the "on state transition / after cooldown / once"
  model) remains a Phase 13/16 item; Phase 14 exposes only the existing cooldown
  setting.
- Nested condition groups are not part of the domain model.
- AI/LLM-assisted rule creation is explicitly out of scope; rules are authored by
  the user.
