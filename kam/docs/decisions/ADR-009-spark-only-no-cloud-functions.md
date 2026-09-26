# ADR-009 — Spark-only architecture: no Cloud Functions, no billing account

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 5 (architectural correction applied before the pairing phase)
- **Supersedes:** the Cloud Functions rows of [ADR-002](ADR-002-firebase-boundaries.md) §3 and the "deferred, with justification" position in `FIREBASE_ARCHITECTURE.md` §7

> **Note on the requested ADR number.** The migration brief asked for
> `ADR-004-remove-cloud-functions-spark-only.md`. `ADR-004` is already taken by
> [ADR-004-configuration-strategy.md](ADR-004-configuration-strategy.md), and
> duplicate identifiers would break the index and every existing cross-reference.
> The canonical decision uses the next free number, ADR-009. A companion copy
> now exists at the requested filename and identifies ADR-009 as canonical.
> Renumbering existing ADRs would invalidate references throughout `docs/` and
> source comments.

## Context

The project has a hard constraint: it must run on the **Firebase Spark (no-cost)
plan** and must never require a credit card, a Cloud Billing account or the Blaze
plan.

ADR-002 fixed the responsibility split for the whole product and explicitly
assigned four responsibilities to Cloud Functions:

| Originally assigned to Cloud Functions | Why ADR-002 put it there |
| --- | --- |
| Issue/validate pairing codes | Codes must be unguessable, expiring and single-use |
| Activate a pair (`pending → active`) | Requires verifying *both* consent documents in a transaction |
| Dispatch notifications | Sending requires privileged credentials |
| Scheduled retention/deletion | Needs to act across users |

Two facts force a correction:

1. **Cloud Functions require the Blaze plan.** Functions have a no-cost usage
   tier, but the product itself is only deployable on Blaze. "It is free within
   the free tier" is therefore not an acceptable answer: the billing account, not
   the invoice, is the problem.
2. **Phase 3 had already, correctly, refused to scaffold a Functions project**
   (`ADR-007` §3, `FIREBASE_ARCHITECTURE.md` §7). So no Functions code exists to
   delete — but the *architecture depended on their arrival*. The rules were
   written to fail closed: no rule permits a client to set `status: 'active'`, so
   pairing was documented as impossible until a function was deployed. Under a
   Spark-only constraint, that makes pairing permanently impossible. This is a
   real functional dependency, not a cosmetic one.

The question this ADR answers is therefore not "how do we remove Functions?" but
**"how do we perform the four trusted operations above without a trusted
server, without making the client the authority on anything?"**

## Decision

Adopt a **Spark-only architecture**. Firebase Authentication, Cloud Firestore,
and the Emulator Suite are used. There is
no Cloud Functions project, no Cloud Run, no Cloud Scheduler, no Pub/Sub, and no
Extensions.

The critical move is a change of mechanism, not a lowering of standards:

> **Authority that a server enforced by *executing code* is now enforced by
> Firestore Security Rules *verifying facts the client cannot forge*. Nothing
> moved into the client's judgement.**

Concretely, for each former Functions responsibility:

### 1. Pair activation (`pending → active`) — Rules verify both consents

The rules read **both** members' consent documents before permitting the
transition:

```
bothConsentsGranted(pairId, memberIds) :=
     consentGranted(pairId, memberIds[0]) && consentGranted(pairId, memberIds[1])
```

Each consent document can only ever be written by its own subject
(`consents/{consentId}` requires `isSelf(consentId)`). Therefore user A cannot
manufacture user B's agreement, and the rule is exactly as strong as the
transaction it replaces. The activation write additionally requires a server
timestamp, so it cannot be backdated.

This also *strengthens* the model: consent becomes the **standing authority**
for sharing. `notPaused()` now requires the owner's consent to be granted, so
revoking consent stops partner reads on the next read rather than waiting for the
owner to also clear a category. That is what NFR-002/NFR-003 describe, and it was
previously only implied.

### 2. Pairing codes — Rules enforce shape, expiry and single-use

Codes are generated on the client with a CSPRNG (`Random.secure`) and published to
`pairingCodes/{code}`. The rules enforce the three properties the function would
have:

| Property | Enforced by |
| --- | --- |
| Unguessable | `code.size() >= 20 && <= 64`, and **`list` is denied** so outstanding codes cannot be harvested |
| Expiring | `expiresAt > request.time && expiresAt <= request.time + duration.value(1, 'h')`, re-checked on every `get` and `update` |
| Single-use | redemption may only change `usedByUserId`/`usedAt`, from `null`, by the redeemer, with a server timestamp |

A code remains a **discovery mechanism only** (FR-003): possessing one grants no
access to device data. Only consent plus sharing categories do that.

### 3. Notifications — the owner's own device writes them

Under Spark there is no server to dispatch notifications, so `users/{uid}/notifications`
is written by the owner's own device when its local rule engine decides a rule
should notify. This is safe only because the collection is **strictly per-user**:
every read and write requires `isSelf(userId)`, so no user can inject content
into another person's notification centre. Content is bounded, the category is
enumerated, `read`/`delivered` must start `false`, the record cannot be backdated,
and title/body/createdAt are immutable after creation.

**Remote push to a partner's device is therefore deferred** — see Consequences.

### 4. Scheduled retention/cleanup — deferred, not delegated

This is the one responsibility that genuinely cannot be moved. A client may only
delete what it owns, and elevating a client to delete across users is precisely
the compromise this ADR exists to prevent. Retention is therefore documented as
policy with lazy, ownership-scoped enforcement (cleanup on access), and
cross-user enforcement is a documented gap.

### 5. Rule evaluation — moved to the client (Category A)

This was ADR-002's "client for the initial scope" row, now made concrete and
complete: `RuleEvaluator` (`features/rules/domain/`) is a pure, deterministic
evaluator. It is safe on the client because its inputs are facts the signed-in
user is already authorized to read, and its output is a *user-defined
interpretation* that grants no access and asserts nothing about another person's
data. Notification *decisions* are likewise local
(`RuleNotificationPlanner`).

## Consequences

**What moved to Flutter:** rule evaluation, notification planning, pairing-code
generation, and the consent/activation *intent* (the state transition is still
authorized by the rules, not by the client).

**What stayed in Firestore Rules:** every authorization decision. Ownership, pair
isolation, category sharing, consent validity, activation gating, code
expiry/single-use, notification privacy, append-only history. Security Rules
remain the only authority; no client-side check is load-bearing.

**What stayed a Firebase client service:** Authentication. FCM token
registration is deferred; no messaging SDK or sending credential is shipped.

**Local notifications:** `RuleNotificationPlanner` and the
`LocalNotificationService` boundary are in place and tested. The default service
reports unsupported; platform alert delivery remains a notification-phase task.

**What is deferred:** remote push delivery to a partner's device (needs a trusted
sender), and cross-user scheduled retention/cleanup (needs a trusted scheduler).

**Cost:** the both-consent check adds a `get()` per partner read. Firestore caches
`get()` results within a single rules evaluation, and the rules already performed
up to two, so the marginal cost is small. `list` denial on `pairingCodes`
prevents an unbounded read pattern.

**Limitation accepted:** rules cannot rate-limit. A pairing code cannot be
brute-forced (20+ characters, CSPRNG-generated, 1-hour maximum life), but an
attacker could *attempt* many guesses; the mitigation is code length and the
no-list rule, not throttling. This is documented rather than papered over.

## Security implications — what must never move to the client

There is no secret in the mobile application, and there must never be one. A value
shipped to a handset is accessible to whoever holds the handset, so obfuscation
(String constants, `.env`, Remote Config, assets, native config) does not make a
secret safe.

The following remain server-only and are **not** implemented anywhere in this
project, because implementing them would require the Blaze plan:

- Firebase Admin SDK service-account credentials (`firebase-adminsdk`, private
  keys, `"type": "service_account"`).
- Any server credential for sending FCM messages (the FCM server key, or a
  service account with `cloudmessaging.messages.create`).
- Any private API key belonging to a third party.

Two invariants are enforced by the build rather than by review:
`test/architecture/spark_only_test.dart` fails if such a credential appears where
it could ship, and fails if `firebase.json` gains a `functions` or `extensions`
block.

## Alternatives considered

- **Keep Cloud Functions and accept Blaze.** Rejected: this is prohibited by the
  project constraint. A no-cost usage tier does not remove the billing account.
- **Replace Functions with Cloud Run / Cloud Scheduler / Pub/Sub.** Rejected: all
  are billed Google Cloud services, so this trades one billing dependency for
  another.
- **Move the whole trust decision into the client** (let a client set
  `status: 'active'` for any pair it belongs to, or write its own notification
  content for others). Rejected outright: it would let one user grant themselves
  access to another person's data, contradicting FR-063/NFR-003 and the core
  privacy promise. This is the trap the ADR exists to avoid.
- **Put a shared secret or an admin credential in the app to emulate a server.**
  Rejected: strictly worse than having no server. A shipped secret is a public
  secret.
- **Derive notifications purely from Firestore listeners with no stored record.**
  Rejected as the *only* mechanism: FR-044 requires the record to survive even
  when delivery fails. The record is now owner-written; delivery is the part that
  degrades.
