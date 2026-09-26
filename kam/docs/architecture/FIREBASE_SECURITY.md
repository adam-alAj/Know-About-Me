# Firebase Security Model

How authorization is enforced for the Mutual Device Presence & Reassurance
System, and how it is verified.

Rules live in `firebase/firestore.rules`; the data they protect is described in
`FIRESTORE_DATA_MODEL.md`. The rules are backed by 31 emulator tests in
`firebase/test/firestore.rules.test.js`.

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

Explicitly **out of scope** for Phase 3: account takeover, device malware,
traffic analysis, and the security of Cloud Functions (none exist yet).

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
3. the owner's sharing document to have the category enabled, and
4. the owner not to have paused sharing.

A completed pairing flow is still not authorization: activation is server-side,
and sharing is a separate, revocable decision (SRS FR-005, NFR-003).

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

## 5. Privileged transitions are server-side only

| Operation | Client | Server |
| --- | --- | --- |
| Create a connection request (`pending`) | ✅ (must include self, must set `createdAt == request.time`) | — |
| Change membership | ❌ (immutable: `memberIds`, `requestedBy`, `createdAt` must be unchanged) | — |
| Activate (`pending → active`) | ❌ **no rule permits it** | ✅ (Admin SDK, Phase 5) |
| End (`→ disconnected` / `revoked`) | ✅ either member | ✅ |
| Write another member's sharing or consent | ❌ | ✅ |
| Create/delete notifications | ❌ | ✅ |
| Update/delete events or interpretations | ❌ | ✅ (retention jobs, Phase 12) |

Fail-closed by construction: if Phase 5's backend does not exist yet, the pair
simply never activates — which is the safe outcome.

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
| Firebase Admin / service-account keys | **Secret** | nowhere in this repository; server-side only |
| Cloud Functions secrets | **Secret** | server-side only |
| FCM server key | **Secret**, and legacy — modern sending uses service accounts | server-side only |

A repository-wide review (Phase 3, Task 25) found: no service-account files, no
private keys, no `.env` files, and no hard-coded credential literals. `.gitignore`
additionally blocks `*.pem`, `*.p12`, `*.jks`, `service-account*.json`,
`*.env*`, `node_modules/`, emulator debug logs and `google-services.json`.

The `client-safe-api-key` strings in `test/unit/firebase_config_test.dart` are
obvious placeholders, not credentials.

**The client never holds a privileged credential**, so it cannot bypass these
rules even if the binary is modified.

---

## 8. How the rules are verified

`firebase/test/firestore.rules.test.js` runs against the Firestore Emulator with
the real rules loaded. 31 tests, all passing:

| Required scenario | Tests |
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
firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"
```

The emulator uses the `demo-kam` project id, which is the documented Firebase
convention for a **local-only** project: it requires no account, no credentials
and cannot touch production data.

---

## 9. Known gaps and follow-ups

1. **Pair activation is not implemented** (needs the Phase 5 backend). Until
   then, `status` cannot leave `pending` in a client-only flow.
2. **Completion of consents is not enforced by rules.** Rules require an *active*
   pair, but they cannot verify that both consent documents exist, because that
   would need a second cross-document read and would race with the activation
   transaction. The activation function must validate both consents in a
   transaction (Phase 5).
3. **No Rules-unit-test coverage for the `devices` collection's delete path** or
   for a 3+-member pair (the model is strictly two-member).
4. **No App Check.** Firebase App Check should be enabled when the app ships, to
   raise the cost of automated abuse; it is not required for the authorization
   model itself.
5. **Rate limiting / abuse protection** is deferred to the Functions phase.
6. **Retention and deletion jobs** (NFR-031, NFR-032) are deferred to Phase 12;
   rules currently allow the owner to delete their own profile, state and location.
