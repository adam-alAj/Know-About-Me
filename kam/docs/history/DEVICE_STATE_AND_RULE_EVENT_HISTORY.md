# Device State and Rule Event History

## Purpose and boundaries

History is a record of discrete device observations and user-authored rule
outcomes. It does not evaluate rules, infer people’s behavior, or retain raw
telemetry. The existing device collectors and deterministic rule evaluator stay
authoritative for facts and evaluations.

```text
device observations ──meaningful transition──┐
rule evaluation ──────outcome transition─────┼─> normalized event
notification decision───────────────────────┘       │
                                           bounded local cache
                                           pair-scoped Firestore
                                           history timeline
```

## Model and taxonomy

`DeviceEvent` is the normalized model. It carries an opaque deterministic event
ID, pair and local device scope, owner, controlled event type/category, the
observation/evaluation time (`occurredAt`), optional source observation time,
optional server-assigned `recordedAt`, source, deduplication key, short summary,
and a small structured payload. The local device ID and pair ID are omitted from
remote event documents; their Firestore path provides the pair scope.

Event categories are device, network, location, charging, rules and
notifications. Types distinguish charging start/stop, connectivity transition,
rule matched/unmatched/unknown, interpretation generation, and notification
shown/suppressed. Exact coordinates, battery percentages, rule IDs/names,
notification content, and raw state snapshots are not event payloads.

## Meaningful change and deduplication policy

* Battery percentage changes do not create events.
* Charging events require two available, differing charging observations.
* Connectivity events require an available online/offline transition. Unknown
  or missing connectivity never means the device powered off.
* Rule events are emitted for `becameMatched`, `becameNotMatched`, and
  `becameIndeterminate`; stable outcomes are ignored. A configured
  interpretation is separately identified when a new match produces one.
* Notification events describe the local decision/result, separately from the
  rule match. No lock-screen text or partner facts are retained.
* Location and activity history are not yet generated. No exact location or
  unsupported activity capability is recorded.

IDs are derived from pair, owner, subject rule (for rule transitions), event
type, transition and observation/evaluation time, then reduced to an opaque
stable value. SharedPreferences rejects repeated IDs. Firestore uses that value
as the document ID and denies document updates, so retries cannot rewrite a
record. Security Rules validate the author, schema, timestamp, type/category,
payload bounds, active pair and the owner’s corresponding sharing category.

## Persistence and queries

Local history uses the existing `shared_preferences` dependency. It is bounded
to 500 events and 180 days, available offline, sorted by server recording time
when available and observation time otherwise, with event ID as a tie-breaker.
Malformed local or remote records are skipped. Clearing history removes the
local cache and attempts to delete the signed-in user’s remote pair events.

Remote history uses the existing configured pair subtree:

```text
pairs/{pairId}/events/{opaqueEventId}
```

Only meaningful transitions are written. The Firestore client assigns
`recordedAt` with `serverTimestamp`; `occurredAt` and `observedAt` represent
device-observed/evaluation times in UTC. The app queries at most 100 newest
events for the active pair, optionally filtered by category. The root index
configuration includes category plus `recordedAt` for filtered timeline reads.
The dashboard preview takes three events from that bounded result.

Firestore offline persistence queues writes while the SDK is offline. Local
history is written first and remains available if Firebase rejects a write.
Deterministic IDs and create-only rules prevent duplicate remote documents.

## Security and privacy

`firebase.json` points to the root `firestore.rules`; that file now matches the
strict pair rules under `firebase/firestore.rules`. Event creation is append-only
and owner-bound. Active pair members can read pair history; after a pair ends,
each member can read/delete only their own event records. Each author’s event
creation requires active mutual consent, unpaused sharing, and the relevant
sharing category. The root and Firebase-directory rules are kept aligned.

History event documents do not contain internal device identifiers, raw rule
IDs, exact coordinates, or raw device snapshots. Rule and notification
descriptions are intentionally generic. User-defined probability remains a
rule interpretation concept and is not presented as a measured probability.

## Retention and cost

Local retention is automatically bounded (500 items / 180 days). The user can
clear local history and their own remote records while the pair scope is
available. There is no server-side scheduled cleanup under the Spark-only
architecture; remote history can grow until users clear it. No Cloud Functions,
Cloud Run, Scheduler, Pub/Sub, Admin SDK, or paid service was added.

Writes occur only for charging/connectivity changes and rule/interpretation/
notification transitions. A repeated stable rule state does not write. A new
match can produce one rule event, an optional interpretation event, and one
notification decision event. The history screen uses one bounded listener per
selected category; the dashboard uses one bounded recent-event listener.

## Known limitations

* Current event generation covers charging, online/offline connectivity, rule
  outcome transitions, interpretation generation, and notification decisions.
  It does not yet create activity, device stale/reachable, network transport,
  or coarse home/away transition events.
* The history screen currently shows a bounded 100-event window; it does not
  yet expose cursor-based load-more pagination.
* Local cache uses SharedPreferences and rewrites its bounded JSON list when an
  event is added. This is suitable for the current small cap, not a large event
  archive.
* Remote retention has no automatic age/count cleanup. Clearing remote events
  is available only while a pair scope is present; after disconnection, the
  local owner copy remains accessible, while future remote deletion needs an
  explicit account/pair cleanup flow.
* Background event collection remains subject to existing Android/iOS
  execution restrictions. No continuous background monitoring is claimed.
* Device clock skew can affect `occurredAt`; Firestore `recordedAt` is used for
  remote ordering. Exact occurrence time is not inferred when the source has no
  observation timestamp.

## Validation

The model has unit coverage for normalized serialization, taxonomy validation,
and separation between rule and notification events. Firestore emulator tests
cover owner-bound immutable creation and deletion. The commands and actual
results are recorded in `PHASE_17_COMPLETION_REPORT.md`.
