# Firebase Security Model

How authorization is enforced for the Mutual Device Presence & Reassurance
System, and how it is verified.

Rules live in root `firestore.rules` (mirrored at `firebase/firestore.rules`);
the data they protect is described in `FIRESTORE_DATA_MODEL.md`. Phase 19
historically recorded 114 passing emulator tests; current emulator validation is
BLOCKED and is not inferred from that historical count.

> **Phase 19** hardened the rules and the client and produced the authoritative
> threat model, enforcement matrix and test matrix in
> [`../security/SECURITY_AND_AUTHORIZATION.md`](../security/SECURITY_AND_AUTHORIZATION.md).
> This document remains the original Phase 3+ authorization narrative.

> **Current configuration:** Firebase project identifiers are present in this
> checkout, but the intended production project is unconfirmed. The rules tests
> use the isolated local `demo-kam` emulator project. See the as-built
> [Firebase architecture](FIREBASE_ARCHITECTURE.md) and
> [final handover](../project/FINAL_PROJECT_HANDOVER.md).
>
> This document contains Phase 3-era examples and test groupings. For current
> enforcement details, use
> [`../security/SECURITY_AND_AUTHORIZATION.md`](../security/SECURITY_AND_AUTHORIZATION.md);
> historical test counts here are not current validation.

---

## 1. Threat model

The app is a two-person privacy product, so the interesting attackers are:

| Attacker | Goal | Defence |
| --- | --- | --- |
| A modified client (the owner's own app binary) | Read a partner's data that the partner did not share, or grant itself access | Every access decision is re-derived server-side from the pair + sharing documents; the client's claims are ignored (constraint 4) |
| Any authenticated user | Read arbitrary other users' data | Path-scoped rules; `users/{uid}` is owner-only and pair data is member-only |
| A member of pair A | Read pair B | Pair isolation: every partner document is nested under `pairs/{pairId}` and the rule checks membership of *that* pair |
| A member of a pending/ended pair | Read shared data without/after authorization | Reads require `status == 'active'`; `disconnected`/`revoked` cut access immediately |
| An unauthenticated client | Read or write application data | Every rule requires `request.auth != null` |
| A user trying to fabricate history or interpretations | Make a configured guess look like a measurement, or forge events | `isUserDefined == true` is required; events and interpretations are append-only and owner-bound |
| Someone with repository access | Obtain privileged credentials | No Admin/service-account credential exists in the client or the repo (`§7`) |

Explicitly **out of scope**: account takeover, device malware, traffic analysis,
and server-side rate limiting (Security Rules cannot throttle).

There is no Cloud Functions project and there will not be one: the architecture
is designed for Spark, so every decision below is enforced by Security Rules
rather than by trusted server code
([ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md)).

---

## 2. Authentication is not authorization

This distinction is the backbone of the model:

```text
Firebase Authentication  →  who you are        (identity)
Firestore Security Rules →  what you may touch (authorization)
```

Being signed in grants access to **your own** documents only. Access to another
person's data additionally requires:

1. an **active pair** (`pairs/{pairId}.status == 'active'`),
2. membership of that pair (`request.auth.uid in memberIds`),
3. the owner's **consent document to be granted**
   (`pairs/{pairId}/consents/{ownerId}.granted == true`),
4. the owner's sharing document to have the category enabled, and
5. the owner not to have paused sharing.

A completed pairing flow is still not authorization: activation requires *both*
users' consent documents, and sharing is a separate, revocable decision
(SRS FR-005, NFR-003). Because consent is checked on every partner read, revoking
it takes effect immediately rather than at the next write.

---

## 3. Pair isolation

```text
pairs/{pairId}                       ← the boundary
  memberIds: [uidA, uidB]
  ...
  deviceState/{ownerId}   ┐
  location/{ownerId}      ├─ everything two people can see about each other
  interpretations/{id}    │  lives under the pair
  events/{eventId}        ┘
```

- Membership is checked against `memberIds` on the enclosing pair document:
  `uid() in pairData(pairId).memberIds`.
- Because the check is on the *enclosing* pair, a member of pair A can never
  satisfy it for pair B — isolation is structural, not a list of exceptions.
- The pair document itself is readable only if `uid() in resource.data.memberIds`,
  so it can also be listed safely (`memberIds array-contains <uid>`).
- Ending a pair sets `status` to `disconnected`/`revoked`. Every shared-data rule
  requires `status == 'active'`, so access stops on the very next request — no
  cleanup job, no propagation delay (FR-054, FR-065).

---

## 4. Field-level minimisation (the part rules normally cannot do)

Firestore rules decide per **document**, not per field: granting `read` on a
document exposes every field in it. The model therefore uses two mechanisms:

**(a) Category gating on write.** A disabled category is never stored:

```javascript
allow create, update: if ownerWritesOwnState();
// where ownerWritesOwnState() requires, for each present field:
//   (!('batteryPercentage' in request.resource.data.keys()) || shares(pairId, ownerId, 'battery'))
//   ... one clause per category-gated field
```

**(b) Category re-checking on read.** Even if a value lingers (for example the
owner disabled a category after writing it), the reader cannot read the document
unless every field it still contains is shared:

```javascript
allow read: if isSelf(ownerId)
  || (isActivePair(pairId) && notPaused(pairId, ownerId)
      && (shares(...,'battery') || shares(...,'charging') || ...)
      && stateFieldsStillShared(pairId, ownerId));
```

Together these mean a modified client cannot make an unshared category readable,
and a bug in the owner's own app cannot leak a category the owner switched off.

**Location** is gated independently, in its own document and its own rule (see
`FIRESTORE_DATA_MODEL.md` §1), satisfying NFR-036: pausing location does not
affect battery/charging/network and vice versa (FR-021).

---

## 5. Privileged transitions without a server

Under Spark there is no trusted process, so each formerly server-only operation
is now gated by a rule on facts the client cannot forge. "Gated by" means the
*client may send the request* but the rules independently verify it — the client
is never the authority.

| Operation | Client | Rules |
| --- | --- | --- |
| Create a connection request (`pending`) | ✅ (must include self, `createdAt == request.time`) | verifies |
| Change membership | ❌ (immutable: `memberIds`, `requestedBy`, `createdAt`) | rejects |
| Activate (`pending → active`) | ✅ may *request* it | ✅ **only if `bothConsentsGranted()`**, i.e. both `consents/{uid}` documents are `granted == true`, with a server timestamp. Each consent can only be written by its own subject, so agreement cannot be forged |
| Resume (`paused → active`) | ✅ may request | ✅ same both-consent gate |
| End (`→ disconnected` / `revoked`) | ✅ either member | allows |
| Write another member's sharing or consent | ❌ | rejects (`isSelf(consentId)`/`isSelf(sharingId)`) |
| Issue a pairing code | ✅ (CSPRNG, ≥20 chars) | ✅ enforces length, `expiresAt` within 1 h and in the future |
| Redeem a pairing code | ✅ | ✅ single use only, by the redeemer, server-timestamped, changing nothing else; `list` denied |
| Create/delete notifications | ✅ **only in its own** collection | ✅ `isSelf(uid)`, enumerated category, `read`/`delivered` must start `false`, no backdating, content immutable after creation |
| Update/delete events or interpretations | ❌ | rejects (append-only) |

This is why the migration is not a weakening. The both-consent rule enforces the
exact invariant a trusted transaction would have: mutual, independently recorded,
unforgeable agreement.

---

## 6. Facts and interpretations are protected by the rules

The product's central rule (SRS FR-030, NFR-023, NFR-041) is enforced at the data
layer, not just in the UI:

```javascript
allow create: if ... && request.resource.data.isUserDefined == true && ...;
```

An interpretation can only be stored when explicitly flagged as user-defined, so a
user-configured percentage can never be persisted as a measured one. Events are
append-only and bound to `ownerUserId == uid()`, so history cannot be forged on
behalf of another user.

---

## 7. Credential handling

| Value | Classification | Where it lives |
| --- | --- | --- |
| Firebase project id, API key, app id, sender id | **Client-safe identifiers** (they ship in every FlutterFire app) | `--dart-define` at build time; `AppConfig` |
| `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json` | Not secret | repository |
| Firebase Admin / service-account keys | **Secret** | nowhere in this repository, and there is no server to hold them — see below |
| FCM server key / sending credential | **Secret**, and legacy — modern sending uses a service account | nowhere in this repository |

Neither secret class is merely "elsewhere": under the Spark-only architecture
there is **no trusted server at all**, so a capability that would need one (remote
push, cross-user retention) is deferred rather than given a credential
([ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md)). A secret
shipped to a handset is a public secret, so obfuscation, `.env`, Remote Config,
assets and native configuration are all equivalent to publishing it.

Repository-wide reviews (Phase 3 Task 25, and again for the Spark migration) found:
no service-account files, no private keys, no `.env` files, and no hard-coded
credential literals. The migration review — covering `service.?account`,
`private.?key`, `client.?secret`, `admin sdk`, `firebase.?admin`, `cloud.?run`,
`scheduler`, `pub/sub`, `FCM_SERVER`, `api.?secret` — matched only documentation
comments. These invariants are now **tests** rather than a one-off audit:
`test/architecture/spark_only_test.dart` fails the build if a privileged
credential appears where it could ship, or if a `functions`/`extensions` deploy
target is added. `.gitignore` additionally blocks `*.pem`, `*.p12`, `*.jks`,
`service-account*.json`,
`*.env*`, `node_modules/`, emulator debug logs and `google-services.json`.

The `client-safe-api-key` strings in `test/unit/firebase_config_test.dart` are
obvious placeholders, not credentials.

**The client never holds a privileged credential**, so it cannot bypass these
rules even if the binary is modified.

---

## 8. How the rules are verified

`firebase/test/firestore.rules.test.js` runs against the Firestore Emulator with
the real rules loaded. Phase 19 reports 114 passing tests; this is historical,
not a current test result. The table below is the original
Phase 3 grouping; the authoritative, current scenario matrix is in
[`../security/SECURITY_AND_AUTHORIZATION.md`](../security/SECURITY_AND_AUTHORIZATION.md) §18.

| Required scenario | Tests (original numbering) |
| --- | --- |
| Unauthenticated access denied | 1, 2 |
| User isolation (A cannot read B's private data) | 3, 4, 5, 6 |
| Pair isolation (A cannot read an unrelated pair) | 7, 8 |
| Authorized active-pair member sees only shared categories | 9, 10, 11, 12, 13 |
| Sharing paused / not enabled blocks reads | 11, 14, 19, 20 |
| Pending pair grants nothing | 15 |
| Disconnected / revoked member loses access | 16, 17 |
| Unauthorized or over-reaching writes rejected | 18, 19, 21, 22, 23, 24 |
| Append-only history and interpretations | 25, 26, 29, 30, 31 |
| Server-only notification creation | 27, 28 |

Run them with:

```bash
cd kam
firebase emulators:exec --project demo-kam --only firestore "node --test firebase/test/firestore.rules.test.js"
```

The test suite initializes contexts with `demo-kam`. Pass `--project demo-kam`
explicitly so Firebase CLI does not inherit the current `.firebaserc` default
`gendersocialapp`. Emulator test data is local; this does not validate deployment
to a Firebase production project.

---

## 8.1 Profile rules (added in Phase 4)

The `users/{uid}` and `users/{uid}/settings/preferences` rules were **strengthened**
for the authentication/profile work. Nothing was relaxed:

| Rule | Why |
| --- | --- |
| create requires `createdAt == request.time && updatedAt == request.time` | a client cannot backdate its own profile |
| update requires `updatedAt == request.time` and `createdAt` unchanged | ownership and creation time are immutable |
| `displayName` must be 1..120 characters on both create and update | matches the client validator, so a value cannot pass the form and fail the server |
| settings writes allow only `notificationPreference`, `homeLocation`, `updatedAt` | the private document cannot be used as arbitrary storage |
| `notificationPreference` must be one of the four known values | prevents a value the app cannot interpret |
| `homeLocation` must have numeric latitude ±90 and longitude ±180 | the most sensitive field the owner stores is range-checked |

The write shapes in `FirestoreProfileRepository` were updated to satisfy these
rules (`FieldValue.serverTimestamp()` everywhere, `update()` rather than `set()`),
and 16 emulator tests cover them in
`firebase/test/firestore.rules.test.js`.

---

## 9. Known gaps and follow-ups

1. **Global duplicate-pair prevention is not enforceable with arbitrary pair IDs
   and no trusted server.** The app uses transaction retries, but a modified
   client could choose a second pair ID. See `docs/pairing/PAIRING_SYSTEM.md`.
2. **Code guessing cannot be server-rate-limited.** Codes have 130 bits of
   client-generated CSPRNG entropy, short expiry, and single-use rules, but the
   rules cannot prove entropy or throttle authenticated attempts.
3. **No Rules-unit-test coverage for the `devices` collection's delete path** or
   for a 3+-member pair (the model is strictly two-member).
4. **No App Check.** Firebase App Check should be enabled when the app ships, to
   raise the cost of automated abuse; it is not required for the authorization
   model itself.
5. **Rate limiting / abuse protection** needs trusted infrastructure if required.
6. **Retention and deletion jobs** (NFR-031, NFR-032) are deferred to Phase 12;
   rules currently allow the owner to delete their own profile, state and location.

### Resolved in Phase 19

- **Rule definitions could not be written at all.** `ruleValid()` referenced
  `request.resource.data.type`/`category`, which a rule document does not carry,
  so every rule create/update failed with a rules evaluation error. The block was
  removed and is covered by the emulator suite.
- **`devices/{deviceId}`, `interpretations/{id}` and `notifications/{id}` now use
  closed field sets** with type, range and length checks, immutable ownership, and
  server-authoritative timestamps where they matter.
- **`sharing` updates must carry `updatedAt == request.time`** and may not be
  padded with extra fields.
- **Protected local state is cleared at session end** and the local history cache
  is read scoped by owner, so one account's cached data is never shown to another.
- **The deployed `firestore.indexes.json` was missing the
  `pairs(memberIds CONTAINS, status)` index** the profile-sync query needs; the
  root and `firebase/` copies are now identical.
