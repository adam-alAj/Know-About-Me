# Firestore Data Model

The Phase 3 Firestore foundation for the Mutual Device Presence & Reassurance
System. It is designed around **access patterns and security boundaries**, not by
creating a collection per noun, and it deliberately follows SRS FR-057/FR-058:
**current state + meaningful events + timestamps**, never high-frequency raw
telemetry.

Companion documents:

- `FIREBASE_SECURITY.md` — the rules that enforce this model.
- `FIREBASE_ARCHITECTURE.md` — service responsibilities and boundaries.

---

## 1. Collections at a glance

```
users/{userId}                                  private profile
users/{userId}/settings/preferences             home location, notification prefs
users/{userId}/rules/{ruleId}                   rule definitions (private)
users/{userId}/fcmTokens/{tokenId}              push tokens (private, never shared)
users/{userId}/notifications/{notificationId}   per-user notifications (server-created)

pairs/{pairId}                                  the security boundary
pairs/{pairId}/members/{userId}                 partner-visible name/photo
pairs/{pairId}/consents/{userId}                each user's own consent record
pairs/{pairId}/sharing/{userId}                 each user's live sharing switches
pairs/{pairId}/devices/{deviceId}               registered devices
pairs/{pairId}/deviceState/{userId}             current non-location state
pairs/{pairId}/location/{userId}                current location (separately gated)
pairs/{pairId}/interpretations/{interpretationId}  rule output
pairs/{pairId}/events/{eventId}                 meaningful history events
```

### Why `pairs/{pairId}` is the boundary

Everything two users can see about each other lives **under the pair**. This
makes pair isolation enforceable by path: a rule can never accidentally expose
user A's data to user B unless B is a member of the enclosing pair. It also makes
revocation immediate — ending the pair cuts off the whole subtree at once.

### Why sharing is its own document

`pairs/{pairId}/sharing/{userId}` is the single source of truth for "is this
category shared right now". Keeping it as one small document per (pair, user),
rather than flags scattered across the pair document or the user document, means:

- the security rules need exactly one extra `get()` to decide a partner read,
- the Flutter `SharingPreferences(userId, pairId)` model maps 1:1,
- a sharing change cannot desynchronise two copies of the same fact.

### Why location is a separate document

Firestore rules cannot grant access to *part of* a document. If location shared a
document with battery state, enabling battery would unavoidably enable location.
Location therefore lives in `pairs/{pairId}/location/{userId}` with its own rule
(NFR-036).

---

## 2. Data ownership

| Entity | Path | Owner | Authorized readers | Authorized writers | Client write allowed? | Retention |
| --- | --- | --- | --- | --- | --- | --- |
| Private profile | `users/{uid}` | the user | owner only | owner | yes (key-validated) | until user deletes |
| Settings | `users/{uid}/settings/preferences` | the user | owner only | owner | yes | until user deletes |
| Rules | `users/{uid}/rules/{ruleId}` | the user | owner only | owner | yes | until user deletes |
| FCM tokens | `users/{uid}/fcmTokens/{tokenId}` | the user | owner only | owner | yes | until token is revoked |
| Notifications | `users/{uid}/notifications/{id}` | the user | owner only | **server only** (create/delete); owner may set `read` | read flag only | later retention policy |
| Pair | `pairs/{pairId}` | both members | members only | members, restricted | limited (see §4) | ended, not deleted |
| Member profile | `pairs/{pairId}/members/{uid}` | the user | pair members | the user themself | yes | while pair exists |
| Consent | `pairs/{pairId}/consents/{uid}` | the user | pair members | the user themself | yes | while pair exists |
| Sharing | `pairs/{pairId}/sharing/{uid}` | the user | pair members | the user themself | yes | while pair exists |
| Devices | `pairs/{pairId}/devices/{deviceId}` | the user's device | pair members | the owner | yes | while pair exists |
| Device state | `pairs/{pairId}/deviceState/{uid}` | the user | owner + partner (shared categories only) | owner | yes (minimised) | overwritten in place |
| Location | `pairs/{pairId}/location/{uid}` | the user | owner + partner (location category only) | owner | yes (location required) | overwritten in place |
| Interpretation | `pairs/{pairId}/interpretations/{id}` | the rule owner | owner + partner (interpretations category) | owner, create only | create only | with pair/history policy |
| Events | `pairs/{pairId}/events/{eventId}` | the recording device's owner | pair members | owner, create only | create only | with history policy (Phase 11) |

**Invariant:** *User A must never be able to read arbitrary User B data.* The only
path from A to B's data is an **active pair** whose owner has **explicitly enabled
that category** and has **not paused sharing**.

### Home coordinates never leave the owner's private settings

`users/{uid}/settings/preferences.homeLocation` is owner-only and is never
returned by a query a partner can run. The partner sees the *derived*
`distanceFromHomeKm` / `homePresence` written into the shared state documents, which
is exactly what SRS FR-023/FR-024 require and satisfies data minimisation
(NFR-005) and location sensitivity (NFR-036).

### Partner display names

`pairs/{pairId}/members/{userId}` holds the denormalised name/photo a partner may
see. It exists so the partner never needs read access to `users/{uid}`, which also
contains private settings.

---

## 3. Device-state storage strategy (SRS Task 12)

One document per (pair, owner) holding the **latest known** values — not a
time series:

| Field | Category gate | Notes |
| --- | --- | --- |
| `batteryPercentage` | `battery` | 0–100 (FR-008) |
| `isCharging` | `charging` | FR-009 |
| `chargingStartedAt` | `charging` | recording when charging began |
| `chargingDurationSeconds` | `charging` | derived (FR-010) |
| `networkState` | `network` | online/offline/wifi/mobile/unknown (FR-012) |
| `availabilityState` | — | reachability only, never "powered off" (FR-015) |
| `lastOnlineAt` | — | last successful sync (FR-014) |
| `activityState` | `activityIndicators` | screen/activity where supported (FR-016) |
| `lastActivityAt` | `activityIndicators` | FR-017 |
| `observedAt` / `updatedAt` | — | freshness (FR-047) |

The **category gate column is enforced by the security rules on write**, so a
disabled category is never persisted, and re-checked on read, so a lingering field
cannot become visible after sharing is switched off. See `FIREBASE_SECURITY.md` §4.

Location fields live in `pairs/{pairId}/location/{userId}`:

| Field | Category gate |
| --- | --- |
| `latitude`, `longitude`, `accuracyMeters`, `placeLabel` | `location` |
| `distanceFromHomeKm`, `homePresence` | `distanceFromHome` |
| `observedAt` | — |

`accuracyMeters` exists so an approximate fix is never presented as exact
(FR-020), and `observedAt` drives the freshness classification (FR-025, NFR-025).

---

## 4. Pair lifecycle, membership and consent

`pairs/{pairId}`:

```text
memberIds:   [uidA, uidB]      // membership; used by every access rule
status:      pending | active | paused | disconnected | revoked
requestedBy: uid
createdAt / updatedAt / activatedAt / endedAt
```

Lifecycle enforcement (SRS NFR-042) is split deliberately:

| Transition | Who may perform it | Why |
| --- | --- | --- |
| `→ pending` | either user (on create) | a user may ask to connect |
| `pending → active` | **server only** | requires *both* consents; a client cannot be trusted to assert that (ADR-002) |
| `active ↔ paused` | server only (Phase 5) | pausing is a mutual-relationship operation |
| `pending/active/paused → disconnected/revoked` | either member | either user can always leave |
| delete | nobody | pairs are ended, never deleted, so history stays auditable |

Because no rule permits a client to write `status: 'active'`, activation is
fail-closed: a modified client cannot create an authorized pair on its own.

`pairs/{pairId}/consents/{userId}` records **each user's own decision**
(`granted`, `grantedAt`, `revokedAt`, `categories`, `locationSharing`). Pairing is
not authorization: no shared data is readable until the pair is active, and the
sharing document separately governs what is exposed (SRS FR-005, NFR-003).

`pairs/{pairId}/sharing/{userId}` is the live switchboard:

```text
paused:     bool
categories: [ 'battery' | 'charging' | 'network' | 'location'
            | 'distanceFromHome' | 'activityIndicators' | 'ruleInterpretations' ]
```

The category list must match `SharingCategory` in the Flutter domain model; the
rules reject anything outside that set.

---

## 5. Rules and interpretations (SRS Task 14)

Rule **definitions** are private: `users/{ownerId}/rules/{ruleId}`, owner-only.
The partner never reads the rules; the partner sees the **interpretation**.

Interpretations are pair-scoped and append-only:

```text
pairs/{pairId}/interpretations/{id}
  ownerUserId, ruleId, message, probabilityPercent,
  isUserDefined: true,        // enforced by the rules
  basis: [ { metric, description, formattedValue } ],
  producedAt
```

`isUserDefined: true` is **required by the security rules**. A user-configured
percentage can therefore never be stored as if it were measured, which makes SRS
FR-030 / NFR-023 / NFR-041 a data-level guarantee rather than a UI convention.
Phase 3 stores the shape; the engine that produces these documents arrives with
the rule-engine phase.

---

## 6. Events (SRS Task 15)

`pairs/{pairId}/events/{eventId}` — meaningful transitions only, never one per
poll:

```text
deviceId, ownerUserId, type, category, occurredAt, recordedAt, summary
```

- `type` mirrors `DeviceEventType` (charging started/stopped, went offline/came
  online, significant location change, rule activated, notification generated,
  connection changed, sharing permission changed).
- `category` mirrors `EventCategory` for history filtering (FR-051).
- `recordedAt` must equal the server timestamp (`request.time`), so ordering is
  trustworthy regardless of client clocks (NFR-035, NFR-043).
- Events are immutable: no client update or delete. Retention and deletion policy
  belongs to a later phase (NFR-031, NFR-032).

---

## 7. Timestamps (SRS Task 16)

| Kind | Representation | Rule |
| --- | --- | --- |
| Server-authoritative records (`recordedAt`, `createdAt` on pairs, notification `createdAt`) | Firestore server timestamp (`Timestamp`, UTC) | clients must use `serverTimestamp()`; the pair create rule requires `createdAt == request.time` and the event rule requires `recordedAt == request.time` |
| Device-observed instants (`observedAt`, `occurredAt`, `chargingStartedAt`) | Firestore `Timestamp`, converted to/from UTC `DateTime` in Dart | the device is the only witness for when *it* observed something, so its clock is authoritative for observation time |
| Derived durations (`chargingDurationSeconds`) | integer seconds | avoids storing two timestamps to express one duration |

Consequences:

- Ordering uses server time (`recordedAt`) for conflict resolution and device
  time (`occurredAt`) for display, so a skewed device clock cannot reorder history.
- Duration-based rule evaluation ("has been offline for 60 minutes") compares a
  stored observation timestamp with the server's `request.time`, so it does not
  depend on client clock agreement (NFR-033).
- `core/time/date_time_utils.dart` is the only place that converts UTC to local
  time for display (NFR-026).

---

## 8. Indexes (SRS Task 17)

Defined in `firebase/firestore.indexes.json`. Only queries the product actually
needs are indexed; single-field queries rely on Firestore's automatic indexes.

| Index | Query it serves | SRS |
| --- | --- | --- |
| `pairs`: `memberIds` CONTAINS + `status` ASC | "my active pair" | FR-006, FR-007 |
| `events`: `category` ASC + `occurredAt` DESC | history filtered by category | FR-051 |
| `events`: `deviceId` ASC + `occurredAt` DESC | one device's history | FR-051 |
| `events`: `ownerUserId` ASC + `occurredAt` DESC | history of a partner's device | FR-051 |
| `interpretations`: `ownerUserId` ASC + `producedAt` DESC | a partner's current interpretations | FR-031, FR-045 |
| `rules`: `enabled` ASC + `createdAt` DESC | the user's enabled rules | FR-033, FR-034 |
| `notifications`: `read` ASC + `createdAt` DESC | unread notifications | FR-041, FR-042 |

No index was added for a hypothetical query. Adding an index costs write
amplification, which matters because NFR-039 (cloud cost) is an explicit
requirement.

---

## 9. Offline, freshness and conflict behaviour (SRS Task 23)

The Flutter client inherits Firestore's offline cache. The application must never
treat cached data as automatically current:

- Every state document carries `observedAt` / `updatedAt`, and the UI classifies
  freshness (`DataFreshness`) rather than assuming currency (FR-061, NFR-025).
- A locally cached partner value is shown with its age, so "offline" and "stale"
  are distinguishable from "current" in the UI (`DataStateView`,
  `FreshnessIndicator`).
- Pending writes are queued by the SDK and flushed on reconnect (FR-060).
- Writes are last-writer-wins at the document level. The device-state document is
  a *snapshot*, so nothing is lost by a newer snapshot replacing an older one, and
  `recordedAt` ordering guards history (NFR-035).
- Sharing changes take effect immediately on the next read, because the rules read
  the sharing document at request time rather than trusting the client.

---

## 10. Cost-awareness (SRS Task 24, NFR-039)

| Risk | Mitigation in this model |
| --- | --- |
| High-frequency telemetry writes | one *current state* document per (pair, user); the client writes only on meaningful change |
| Location write storms | location shares the same "meaningful change" policy, and is a single document |
| Listener fan-out | the dashboard listens to a bounded set of documents (pair, partner state, partner location, interpretations), not to event history |
| Rule-evaluation reads | rules are evaluated against the *current state documents*, not by scanning event history |
| Event history growth | events are meaningful transitions only; retention is a later phase |
| Token churn | one token document per device, rewritten on refresh rather than appended |
| Rules engine `get()` cost | partner reads need at most **two** document lookups (pair + sharing), well inside the per-request limit |

---

## 11. Known limitations of this model

1. **One active device per user per pair.** `deviceState` and `location` are keyed
   by user id. Supporting several devices means keying by `deviceId` and adding a
   documented query; the device *registry* (`devices/{deviceId}`) is already
   multi-device, so the change is contained.
2. **`memberProfiles` denormalisation.** A partner's display-name change must be
   written to `pairs/{pairId}/members/{uid}` for each pair. Phase 5 should update
   it when a profile changes.
3. **Pair activation requires the backend.** No Cloud Function exists yet, so a
   pair cannot become `active` in a client-only flow. This is intentional and
   fail-closed.
4. **Retention and deletion** of events/interpretations are not implemented
   (deferred to Phase 12).
5. **`basis` is stored as a plain array** on each interpretation. If
   interpretations grow large, they should be replaced by a reference to the
   state snapshot they were derived from.
