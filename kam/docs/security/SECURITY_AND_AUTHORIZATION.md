# Security, Authorization & Firebase Security Rules

Authoritative security model for the Mutual Device Presence & Reassurance System
(Phase 19). It describes **what is enforced, where, and what is explicitly not**.

Companion documents:

| Document | Contents |
| --- | --- |
| `docs/architecture/FIREBASE_SECURITY.md` | The original rules/authorization narrative (Phases 3+) |
| `docs/architecture/FIRESTORE_DATA_MODEL.md` | Collections, ownership, retention |
| `docs/architecture/SPARK_ONLY_ARCHITECTURE.md` | Why there is no server |
| `docs/pairing/PAIRING_SYSTEM.md` | Pairing UX and its limits |
| `docs/PARTNER_REASSURANCE_DASHBOARD.md` (ui) | What the dashboard renders |

The enforcement boundary is **`firestore.rules`** (deployed from `kam/firestore.rules`,
mirrored at `kam/firebase/firestore.rules`). The rules are backed by **114 emulator
tests** in `kam/firebase/test/firestore.rules.test.js`.

---

## 1. Threat model

This is a private, two-person system (`User A ↔ User B`). It is **not** a public
multi-user platform, so the security model is deliberately small enough to audit:
strict pair isolation, explicit mutual consent, least privilege.

The attacker we design against is **an authenticated user with a modified client**
— someone who can read the shipped binary, change request payloads, replay them,
and forge any field the client controls. The client is never a trust boundary.

| # | Threat | Defender (enforcement point) |
| --- | --- | --- |
| A | Malicious authenticated user reads another user's data | Path-scoped rules; `users/{uid}` is owner-only, everything else is pair-scoped |
| B | Member of pair X reads pair Y | Membership is checked on the **enclosing** `pairs/{pairId}` document, so cross-pair access is structurally impossible |
| C | Client changes `pairId` in a request | The path *is* the pair id; rules resolve membership from that exact document |
| D | Client changes `userId`/`subjectUserId`/`ownerId` to impersonate | Rules compare against `request.auth.uid` **and** the stored document field; a forged field is rejected |
| E | Client reads/writes another device's state | `deviceState/{ownerId}` and `location/{ownerId}` require `isSelf(ownerId)` to write; `deviceId` is never authorization evidence |
| F | Client sets `sharingEnabled = true`, or reads a disabled category | Sharing is derived from `pairs/{pairId}/sharing/{uid}` and re-checked on every read and write; the client cannot write another member's sharing document |
| G | A revoked/disconnected/paused partner keeps access | Every partner read requires `isActivePair` (status `active` **and** both consents granted); pause is re-checked per document |
| H | A pairing code is reused after acceptance/expiry/cancellation | Redemption is a single-use transition guarded by `usedByUserId == null`, a live `expiresAt`, and `revoked == false` |
| I | A third account joins an existing pair | `memberIds` has exactly two entries on create and is **immutable** on update |
| J | Client forges another user's device state | `ownerUserId` must equal both `request.auth.uid` and the path segment |
| K | Client forges a historical event as another user | `events` require `ownerUserId == uid()`, a server `recordedAt`, and are append-only |
| L | Client modifies another user's rules | Rule definitions live at `users/{uid}/rules`, which is owner-only |
| M | Client creates/modifies another user's alerts or history | Notifications and events are strictly per-user; updates are denied or limited to read/delivered flags |
| N | Stale cached authorization is used after revocation | Authorization is re-derived server-side on **every** request; the local cache can only ever produce a rejected request |
| O | An offline client reconnects and uploads stale unauthorized data | Rules re-check current consent, pair status, pause and category on the write; rejected writes are surfaced, not blind-queued |
| P | Sensitive identifiers leak through logs, errors, notifications or local storage | Log redaction, generic lock-screen text, privacy-minimised events, and session-scoped local caches |

Explicitly **out of scope**: account takeover (weak password, phishing), device
malware, network traffic analysis, and server-side rate limiting (Security Rules
cannot throttle: see §16).

---

## 2. Authentication

- Firebase Authentication is the only identity provider; no custom password
  storage exists and no credential is retained by the app
  (`FirebaseAuthRepository` passes credentials straight to the SDK).
- Every rule begins from `signedIn()` (`request.auth != null`). Unauthenticated
  access to *any* application document is denied.
- Firebase configuration values (`projectId`, `apiKey`, `appId`,
  `messagingSenderId`) are **client-safe identifiers**, not secrets. They are
  supplied by `--dart-define` and read through `AppConfig`. A partial
  configuration is treated as *not configured* (fail closed).
- No Firebase ID token, refresh token, Admin credential or service-account key is
  ever logged, stored or shipped. `test/architecture/spark_only_test.dart`
  fails the build if a privileged credential marker appears anywhere it could
  ship.
- Logging redaction: `AppLogger.sensitiveKeys` (`password`, `token`, `apiKey`,
  `secret`, `email`, `latitude`, `longitude`, `location`, …) are replaced with
  `***` before an entry is emitted.
- Error mapping (`FirebaseErrorMapper`) turns SDK errors into the app's own
  `AppFailure` vocabulary. Raw SDK text is never shown, and wrong-password /
  user-not-found produce one identical, vague message (no account enumeration).

---

## 3. User identity binding

`request.auth.uid` is the **authoritative identity**. The rules never trust a
client-supplied `userId`, `ownerId` or `subjectUserId` to decide *who* the caller
is. Every ownership check combines both:

```javascript
request.resource.data.ownerUserId == uid()          // caller claims
&& request.resource.data.ownerUserId == resource.data.ownerUserId  // and matches storage
```

and, wherever the document is keyed by user, also the path segment:

```javascript
isSelf(ownerId) && request.resource.data.ownerUserId == uid()
```

A client can therefore never make a document "belong to" someone else, and can
never promote itself by writing a field such as `isAdmin`, `isAuthorized`,
`isPartner` or `status` (the allowed field sets are closed).

---

## 4. Pair authorization

```text
pairs/{pairId}                     ← the security boundary
  memberIds: [uidA, uidB]          ← immutable, exactly two
  status: pending|active|paused|disconnected|revoked
  deviceState/{ownerId}            ┐
  location/{ownerId}               │ everything two people may see about
  interpretations/{id}             │ each other lives *under* the pair
  events/{eventId}                 │
  members/{uid}  consents/{uid}    │
  sharing/{uid}   devices/{deviceId}┘
```

`isMember(pairId)` is `uid() in get(pairs/{pairId}).memberIds`. Because the check
is against the *enclosing* pair document, membership of pair A can never satisfy
it for pair B — isolation is structural, not a list of exceptions.

A signed-in user can only list pairs they belong to:

```javascript
allow read: if signedIn() && uid() in resource.data.memberIds;
// queried as: where('memberIds', arrayContains: uid)
```

---

## 5. Sharing authorization

Consent and sharing are **separate, revocable decisions** stored per (pair, user):

```text
pairs/{pairId}/consents/{uid}   { userId, pairId, granted, categories, grantedAt }
pairs/{pairId}/sharing/{uid}    { userId, pairId, paused, categories, updatedAt }
```

- Both documents are keyed by the *subject* uid, and the rule requires
  `isSelf(consentId)` / `isSelf(sharingId)`. **User B can never modify User A's
  consent or sharing.**
- `isActivePair(pairId)` requires `status == 'active'` **and**
  `bothConsentsGranted` — the rules read *both* consent documents, so mutual
  consent cannot be forged by one client.
- A partner read of a category additionally requires `notPaused(pairId, ownerId)`
  and `shares(pairId, ownerId, category)`.
- **Field-level minimisation.** Firestore rules decide per document, not per
  field, so the category boundary is enforced twice:
  - on **write**, a gated field may only be present if its category is shared
    (`deviceStateWriteValid`, `locationWriteValid`) — a disabled category is
    never stored;
  - on **read**, every field still present in the document must *still* be shared
    (`stateFieldsStillShared`, `locationFieldsStillShared`) — a lingering value
    cannot become visible after sharing is switched off.

Category set (mirrored from `SharingCategory` in Dart): `battery`, `charging`,
`network`, `location`, `distanceFromHome`, `activityIndicators`,
`ruleInterpretations`.

---

## 6. Device-state authorization

```text
pairs/{pairId}/deviceState/{ownerId}   battery, charging, network, activity, availability
pairs/{pairId}/location/{ownerId}      coordinates + derived home distance/presence
```

| Operation | Requirement |
| --- | --- |
| Owner writes own state | `isSelf(ownerId)` + active pair + own consent + not paused + **closed field set** + typed/ranged values + `updatedAt == request.time` + non-regressing `stateVersion` |
| Owner writes own location | same, plus coordinates in ±90/±180 and `distanceFromHome` gated by its **own** category |
| Partner reads | active pair + not paused + at least one shared category + every present field still shared |

`deviceId` is an opaque, application-generated 128-bit value. It is **never**
authorization evidence — the path and the authenticated uid are. Hardware
identifiers (IMEI, serial, MAC, advertising id) are never collected, and
`devices/{deviceId}` rejects arbitrary fields (so a hardware id cannot be
smuggled in).

**Location is gated independently** (NFR-036): pausing or disabling location does
not affect battery/charging/network, and vice versa.

---

## 7. History authorization

```text
pairs/{pairId}/events/{eventId}   append-only, owner-bound, minimized
```

- A member may create events **for their own device only**
  (`ownerUserId == uid()`), only while the pair is active and not paused, and only
  for a category they currently share (the `type`/`category` pair must match a
  shared category).
- `recordedAt == request.time` (server-authored) and `occurredAt` may not be
  arbitrarily future-dated. `observedAt` is preserved as the real platform
  observation time and is **not** rewritten with server time.
- The field set is closed (`validEvent`) and the `payload` is bounded to
  `{ transition, ruleVersion, outcome }` — no coordinates, no metric values.
- Updates are denied outright; the owner may delete their own events (NFR-032).
- Reads require membership, and partner reads require the pair to still be
  `active` with mutual consent. A revoked or disconnected pair stops partner
  history access on the very next request; the owner keeps access to their own
  records.

**Residual (documented) risk — see §19.4:** because one query returns the
combined timeline of both members, a per-category read gate would reject the whole
query whenever any single event's category is currently disabled. The design
therefore gates event *creation* on the category and gates reads on an
active, mutually-consented pair. History that was recorded while a category was
shared is not retroactively retracted; the owner can delete it.

---

## 8. Rule authorization

```text
users/{uid}/rules/{ruleId}   private to the owner — never partner-readable
```

- `allow read, delete: if isSelf(userId)`; create/update require ownership, a
  closed field set, type/range-checked values, and server timestamps.
- `createdAt` is immutable, so an edit cannot rewrite when a rule was created.
- The partner only ever sees the **interpretations** a rule produces (and only
  while `ruleInterpretations` is shared). A partner cannot read, edit, disable or
  delete another user's rules, and the rules cannot be listed by a partner.

> **Phase 19 fix (High).** `ruleValid()` previously contained an events-specific
> `type`/`category` block. A rule document carries neither field, so
> `request.resource.data.type` evaluated to *undefined* and **every** rule
> create/update was denied with an evaluation error. The block was removed; the
> emulator suite now covers the create/edit/delete path. This is exactly the
> class of bug the rules tests exist to catch.

---

## 9. Interpretation authorization

```text
pairs/{pairId}/interpretations/{id}   append-only, partner-readable only in full
```

- `create` requires an active pair, that the caller is the owner, that
  `isUserDefined == true`, that the owner has not paused, and that the owner
  shares `ruleInterpretations`.
- The document is a **closed, bounded shape** (owner, ruleId, message ≤ 500
  chars, probabilityPercent 0–100, basis ≤ 16 entries, producedAt, schemaVersion).
- `update`/`delete` are denied: an interpretation is a record, not a mutable
  value.
- The SRS invariant "a configured percentage must never masquerade as a measured
  one" is enforced at the data layer: `isUserDefined == true` is required to
  store one.

Evaluation itself is client-side (`RuleEvaluationController`) and is driven by
`authorizedPartnerDeviceStateProvider`, which resolves to `null` the moment the
pair is not active, sharing is paused, or the partner's sharing document is
missing/cached — so rule evaluation stops rather than continuing on stale,
no-longer-authorized data.

---

## 10. Notification security

Under Spark there is no server to dispatch a push, so notifications are **local**
to the observing device: the owner's own device raises a platform notification and
writes a per-user Firestore record at `users/{uid}/notifications/{id}`.

- Records are strictly per-user: every write requires `isSelf(userId)`. No user
  can inject, read or modify another user's notification centre.
- `create` requires a closed field set, bounded title/body, an enumerated
  category, a server `createdAt`, and `read == false && delivered == false`.
  `update` may only touch `read`/`delivered` (a record cannot be rewritten into a
  different message).
- **Lock-screen privacy.** The presented notification is deliberately generic —
  title `Rule alert`, body "A rule you created matches shared device state. Open
  the app to review it." No partner name, no coordinates, no rule text, no
  Firestore path, no identifiers.
- **Tap-time authorization.** A tap opens the app through the normal launch
  intent; it carries at most an opaque `ruleId` extra and is never treated as
  proof of current authorization. The router guard and every data provider
  re-check the live session and pair state, so a notification created while a pair
  was active shows nothing after revocation. The notification payload is a
  deep-link hint, not a capability.

---

## 11. Local data security

Local state lives in app-private `shared_preferences` under keys declared in
`lib/core/storage/sensitive_local_data.dart`.

| Key | Contents | Cleared on sign-out |
| --- | --- | --- |
| `history_events_v1` | bounded offline history cache (500 events / 180 days) | ✅ |
| `device_state.last_known_location` | the single most recent location fix (no trail) | ✅ |
| `device_state.last_observed_activity_at` | last observed activity timestamp | ✅ |
| `device_state.last_online_at` | last observed online timestamp | ✅ |
| `device_state.opaque_device_id` | random opaque device id (**not** user data) | ❌ deliberately |
| `device_state.sync_version` | monotonic per-device state version | ❌ deliberately |

- **Never stored:** Firebase ID tokens, Admin/service-account credentials, API
  secrets, private keys, raw pairing codes.
- The history cache is device-wide, so reads **must** be scoped by
  `ownerUserId`. `historyEventsProvider` resolves the signed-in uid first and
  returns nothing when there is none — a cached timeline can never be rendered to
  a different account that signs in on the same device (NFR-004).
- Session end clears the cached location/activity/history
  (`SensitiveLocalData.clear()`), whether the user signed out or the session was
  revoked/expired elsewhere. Device identity and the sync version are kept on
  purpose: the id identifies the handset, and resetting the version would make the
  device's next legitimate write look older than the stored document and be
  rejected by the rules.

---

## 12. Firestore Rules architecture

Structure of `firestore.rules`:

```text
default deny (no match, no access)
  helpers: signedIn, uid, isSelf, isMember, isActivePair,
           bothConsentsGranted, notPaused, shares, canReadShared,
           stateFieldsStillShared, locationFieldsStillShared,
           deviceStateWriteValid, locationWriteValid, versionNotRegressing
  /users/{uid}                          owner-only profile, settings/preferences,
                                        rules, fcmTokens, notifications
  /pairingCodes/{code}                  get/deny-list/create/single-use-update
  /pairs/{pairId}                       member read, invitation-bound create,
                                        consent-gated immutable-membership update
    /members /consents /sharing /devices
    /deviceState /location /interpretations /events
```

Principles applied:

1. **Default deny** — nothing is readable/writable unless an explicit rule allows
   it. Obscure collection names are not a control.
2. **Least privilege** — closed field sets (`keys().hasOnly(...)`), bounded
   strings/arrays, type and range checks, and enumerated values on every
   client-writable security-relevant document.
3. **Immutable identity/ownership** — `ownerUserId`, `userId`, `pairId`,
   `memberIds`, `requestedBy`, `createdAt`, `deviceId` are verified against the
   stored document on update.
4. **Server-authoritative security timestamps** — `createdAt`/`updatedAt` must
   equal `request.time` where they matter. Real *observation* times
   (`observedAt`, `occurredAt`) are preserved as platform-reported values rather
   than replaced with server time.
5. **No client-supplied privilege** — there is no field a client can write that
   grants access; authorization is re-derived from `request.auth.uid` and trusted
   stored relationships.

---

## 13. Pair lifecycle security

```
created ──► pending ──► active ──► paused ──► active (resume)
                 │          │          │
                 └──────────┴──────────┴──► disconnected | revoked
```

| Transition | Who | Rule requirement |
| --- | --- | --- |
| `pending` create | the redeemer | atomically redeemed, live, unconsumed invitation; `memberIds.size() == 2`; contains self; `requestedBy == uid()`; server timestamps |
| `pending/paused → active` | either member may *request* | **both** consent documents `granted == true`; `activatedAt == request.time` |
| `active → paused` | either member | expressed through their own `sharing.paused` (not a pair status field) |
| `→ disconnected/revoked` | either member | always available; `endedAt == request.time` |
| membership change | nobody | `memberIds` immutable on update |
| delete | nobody | pairs are ended, not deleted (history stays auditable) |

A client cannot activate a pair by writing `status = 'active'`: activation
requires both members' independently-written consent documents, which each member
can only write for themselves.

---

## 14. Revocation & disconnect

Ending a relationship (`disconnected` or `revoked`) or withdrawing consent makes
`isActivePair` false, so on the **very next request**:

- partner reads of `deviceState`, `location`, `interpretations` and `events` are
  denied;
- partner writes are denied;
- the client's streams resolve to "no authorized pair", so the sync coordinator
  stops publishing, partner listeners are cancelled, rule evaluation stops, and
  the dashboard shows no protected partner data.

There is no cleanup job and no propagation delay, because nothing is *pushed* —
authorization is re-derived per request. Locally, the affected providers
recompute on the identity/pair change, and cached partner data is not presented
(and is cleared on session end, §11).

---

## 15. Offline authorization & queued writes

- Firestore's SDK queues writes while offline. A queued write was authorized when
  it was *created*, not when it is *sent*.
- Queued writes are therefore **not** trusted: when connectivity returns, the
  rules re-evaluate the write against the *current* pair status, consent, pause
  state, sharing categories and ownership. A write that was legal when queued but
  is no longer authorized is rejected with `permission-denied` and never applied.
- The app surfaces that rejection through `FirebaseErrorMapper`
  (`PermissionFailure`) and does not retry it blindly; sharing changes are applied
  as merge writes that also delete the fields of a just-disabled category, so a
  retraction and the state update travel together.
- A fully offline device **cannot** instantly learn that the partner revoked
  access. It can keep reading whatever Firestore's local cache already holds. This
  is an unavoidable property of an offline-capable client and it is bounded by:
  cached partner state is never presented as current (`isFromCache` → the
  dashboard shows freshness/age), and the next online request is re-authorized.

---

## 16. Pairing-code limitations (no fake rate limiting)

- Codes are generated client-side with `Random.secure()` (CSPRNG): 26 characters
  from a 32-symbol alphabet ≈ **130 bits** of entropy, far beyond guessing.
- Rules enforce the security-relevant properties: length ≥ 20, `expiresAt` in the
  future and within one hour, `revoked == false`, single-use redemption
  (`usedByUserId` may only move from `null` once), and **`list` is denied** so
  outstanding codes cannot be harvested. Guessing an individual 130-bit code is
  infeasible; enumerating the collection is impossible.
- **No server-side rate limiting exists.** Under Spark there is no trusted backend
  to throttle authenticated attempts, and Security Rules cannot throttle. Any
  client-side attempt counter is a UX affordance, **not** a security boundary, and
  is documented as such. Do not claim server-grade abuse protection.
- A code is a discovery mechanism only: possessing it grants **no** access to
  device data. Only consent + sharing categories do.

---

## 17. Firebase Spark limitations

The project must run on the Spark (no-billing) plan. Therefore:

- **No** Cloud Functions, Cloud Run, Cloud Scheduler, Pub/Sub, Extensions,
  Firebase Admin SDK or service account exists — and none may be added
  (`test/architecture/spark_only_test.dart` enforces this, plus the absence of a
  `functions`/`extensions` deploy target in `firebase.json`).
- Firestore Security Rules are the **primary and only** backend authorization
  mechanism.
- Operations a server would normally perform are replaced by rules that verify
  facts the client cannot forge (both-consent activation, single-use
  invitation redemption, per-user notification records).
- Consequences: no remote push and no cross-user scheduled cleanup. See
  `docs/architecture/SPARK_ONLY_ARCHITECTURE.md`.

---

## 18. Security test matrix

The rules are verified by the Firestore Emulator with the real rules loaded. Run:

```bash
cd kam
firebase emulators:exec --only firestore "npm --prefix firebase test"
```

`demo-kam` is a `demo-` prefixed project id: no account, no credentials, local
data only.

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | Anonymous reads pair/user data | **DENY** |
| 2 | Anonymous writes / creates a pair | **DENY** |
| 3 | User A reads own state | ALLOW |
| 4 | User A writes own state (active pair, valid fields) | ALLOW |
| 5 | User A writes User B's state | **DENY** |
| 6 | User B reads User A's battery/network while shared | ALLOW |
| 7 | User B reads User A's location while `location` not shared | **DENY** |
| 8 | User B reads User A's location while `location` shared | ALLOW |
| 9 | Owner writes a category they have not shared | **DENY** |
| 10 | Partner reads while sharing is paused | **DENY** |
| 11 | Paused owner keeps publishing state | **DENY** |
| 12 | User C reads A/B pair data or history | **DENY** |
| 13 | User C writes A/B state | **DENY** |
| 14 | Forged `pairId` (read/write into a foreign pair) | **DENY** |
| 15 | Forged `userId`/`ownerUserId` on device state | **DENY** |
| 16 | Forged `ownerUserId` on an event | **DENY** |
| 17 | Forged `ownerUserId` on a rule / interpretation | **DENY** |
| 18 | Privilege field (`isAdmin`, `isAuthorized`, `status`, `activatedAt`) on a profile | **DENY** |
| 19 | Partner modifies User A's consent or sharing document | **DENY** |
| 20 | Revoked pair: partner reads state/history | **DENY** |
| 21 | Revoked pair: owner reads own records | ALLOW |
| 22 | Disconnected pair: either member writes state | **DENY** |
| 23 | Pending pair: partner reads shared state | **DENY** |
| 24 | One-sided consent activates a pair | **DENY** |
| 25 | Both consents granted → activation | ALLOW |
| 26 | Revoking consent stops partner reads immediately | **DENY** |
| 27 | Valid invitation → single authorized redeem + pending pair | ALLOW |
| 28 | Expired invitation redeemed | **DENY** |
| 29 | Already-consumed invitation reused (same or different user) | **DENY** |
| 30 | Redeeming an invitation cannot smuggle other changes | **DENY** |
| 31 | Non-issuer cancels an invitation | **DENY** |
| 32 | Pair created with three members / third member added | **DENY** |
| 33 | History: immutable (update/delete another's) | **DENY** |
| 34 | History: field outside the minimized schema | **DENY** |
| 35 | History: category not currently shared | **DENY** |
| 36 | Rule: create/update/delete another user's rule | **DENY** |
| 37 | Interpretation created without `isUserDefined == true` | **DENY** |
| 38 | Interpretation without sharing `ruleInterpretations` | **DENY** |
| 39 | Interpretation with extra fields / oversized message | **DENY** |
| 40 | Notification written into another user's collection | **DENY** |
| 41 | Notification with a forged recipient / extra fields / backdated | **DENY** |
| 42 | Device record bound to another owner or path / hardware id smuggled | **DENY** |
| 43 | Sharing change backdated or padded with unknown fields | **DENY** |
| 44 | State snapshot older than the stored `stateVersion` | **DENY** |
| 45 | State values out of range or wrong type | **DENY** |
| 46 | Client-authored security timestamp (`createdAt`/`updatedAt`) | **DENY** |
| 47 | Firestore query compatibility: `where('memberIds', arrayContains: uid)`; pairing `list` denied | ALLOW / **DENY** |

Rules are **not filters**: a query that could return a document the caller may
not read is rejected as a whole. Every query in the app is therefore owner-,
pair- or document-scoped (see §19.3).

Flutter-side coverage (`flutter test`, 617 tests) additionally covers: the
authentication guard and routing, log/credential redaction, the error mapper's
non-disclosure, session cleanup of protected local state, and owner-scoped local
history reads.

---

## 19. Known limitations

1. **No trusted server / no server-side rate limiting** (§16). Client-side
   throttling is UX only.
2. **No server-enforced global pair uniqueness.** With client-chosen pair ids and
   no server, a modified client could create a second pair document. Membership
   immutability and consent gating still apply to each document. See
   `docs/pairing/PAIRING_SYSTEM.md`.
3. **Queries must be compatible with the rules.** Because rules are not filters,
   broad reads are rejected. The app issues only owner/pair-scoped queries, and
   `collectionGroup` is never queried. Any future broad query must be
   rule-compatible or it will simply fail (fail-closed).
4. **History is not category-retracted after the fact** (§7). Reads require an
   active, mutually-consented pair; per-category read gating would break the
   combined timeline query, so categories gate *creation* instead. The payload is
   minimised and the owner can delete their own events.
5. **An offline device cannot instantly learn a remote revocation** (§15). Bounded
   by "cached is not current" presentation and per-request re-authorization.
6. **No App Check.** Enabling App Check when the app ships would raise the cost of
   automated abuse; it is not required by the authorization model itself.
7. **Cross-user retention/cleanup is not scheduled** (needs a scheduler; Spark has
   none). Deletion is ownership-scoped and user-triggered.
8. **`pairingCodes` `get` returns the document as a whole**, so a user who already
   possesses a live code also sees its `createdByUserId`. The code is 130-bit
   random and unlistable, so this is not reachable by enumeration; it is recorded
   here for completeness.

---

## 20. Security assumptions

1. Firebase Authentication correctly establishes identity; `request.auth.uid` is
   trusted by the Security Rules and `request.auth == null` means unauthenticated.
2. **Firestore Security Rules are the backend authorization boundary.** Anything
   enforced only in Flutter is a UX affordance, not a control.
3. The client binary is potentially modifiable by an attacker, who can inspect,
   modify, replay and forge requests.
4. A malicious authenticated user may attempt to change any client-supplied field
   (`pairId`, `userId`, `ownerId`, `deviceId`, `sharingEnabled`, `isAuthorized`,
   …). None of these are trusted for authorization.
5. An offline device cannot instantly know that remote authorization changed.
6. The Spark-only architecture provides no trusted custom server, so no
   server-side rate limiting, scheduled cleanup or push delivery exists.
7. Platform APIs may report incomplete device state; unavailable capabilities are
   represented explicitly (`unknown`/`unsupported`) and never fabricated.
8. A hidden widget is not protected data, and a notification payload is not proof
   of current authorization.

```text
IDENTITY → AUTHENTICATION → PAIR MEMBERSHIP → CONSENT → SHARING AUTHORIZATION
        → RESOURCE OWNERSHIP → FIRESTORE SECURITY RULES → AUTHORIZED DATA
```
