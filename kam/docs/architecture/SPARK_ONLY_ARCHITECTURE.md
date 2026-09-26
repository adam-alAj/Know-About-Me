# Spark-only architecture

**Status:** current. Supersedes the Cloud Functions plan in
`FIREBASE_ARCHITECTURE.md` §7 and the Functions rows of
[ADR-002](../decisions/ADR-002-firebase-boundaries.md).

This document explains how the product performs every operation that would
otherwise require a trusted server, using only Firebase services available **on
the Spark (no-cost) plan with no Cloud Billing account**. The decision record is
[ADR-009](../decisions/ADR-009-spark-only-no-cloud-functions.md); the checklist
is [SPARK_COMPATIBILITY_CHECKLIST.md](../SPARK_COMPATIBILITY_CHECKLIST.md).

**Phase 5 correction:** rules now bind pair creation to invitation redemption
and require two consent documents for activation. Client CSPRNG quality is not
provable by rules, and Spark rules cannot globally prevent a modified client
from creating a duplicate pair under another pair ID. See
[PAIRING_SYSTEM.md](../pairing/PAIRING_SYSTEM.md) for the concrete limits.

---

## 1. Why there is no server

Cloud Functions are only deployable on the **Blaze** plan. Cloud Run, Cloud
Scheduler and Pub/Sub are likewise billed Google Cloud services. Since the
project may not attach a billing account, none of them can be part of the
architecture — regardless of how much of their usage would fall inside a free
tier. That is a constraint on *deployability*, not on cost.

The consequence that mattered: Phase 3 had deliberately made pair activation
**server-only** (`no rule permits a client to set status: 'active'`), so under a
Spark-only constraint pairing would never work at all. Correcting that is the
functional heart of this change.

Two things were therefore true at the start of the migration and shaped it:

- **No Cloud Functions code existed** to remove (`functions/` has never been
  scaffolded, `firebase-functions`/`firebase-admin` were never dependencies).
- **An architectural dependency on Functions did exist**, recorded in ADR-002,
  `FIREBASE_ARCHITECTURE.md` §7 and `ARCHITECTURE.md` §16.

So this was a redesign of *responsibility*, not a deletion of code.

---

## 2. Cloud Functions audit

Every server-side operation that was planned or implied anywhere in the
repository, with its replacement. "Category" uses the classification from the
migration brief: **A** safe client logic, **B** Firestore-native,
**C** Firebase client service, **D** genuinely needs a trusted server.

| # | Existing/planned logic | Why it existed | Trigger | Data access | Needs trusted server? | Category | Replacement |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Activate a pair (`pending → active`) | Verify both consents in one transaction (FR-005, NFR-003, NFR-042) | Either member finishes consenting | Reads both `consents/{uid}` docs | **Was** believed to be yes | **B** | **Firestore Rules.** `bothConsentsGranted()` reads both consent docs; each can only be written by its owner, so the invariant cannot be forged |
| 2 | Issue/validate a pairing code | Codes must be unguessable, expiring, single-use (FR-003, FR-004) | User starts a connection | Writes `pairingCodes/{code}` | No | **A + B** | **Client CSPRNG + Rules.** `Random.secure` generates ≥20 chars; rules enforce length, ≤1h expiry, single-use, and deny `list` |
| 3 | Dispatch a notification | Sending needs privileged credentials (FR-041, FR-044) | A rule matches | Writes the recipient's notifications | Partly | **A + C** | **Local notifications.** `RuleNotificationPlanner` decides; the owner's device raises the alert and records it in `users/{uid}/notifications`. **Remote push is deferred** |
| 4 | Rule evaluation | Compute an interpretation from device state (FR-026–FR-040) | Device state changes | Reads state the user may already read | No | **A** | **Client.** `RuleEvaluator` — pure, deterministic, clock-injected |
| 5 | Scheduled retention/deletion | Act across users after a period (NFR-031, NFR-032) | Time | Cross-user delete | **Yes — genuinely** | **D** | **Deferred.** Policy documented; ownership-scoped lazy cleanup only. Cross-user enforcement is a documented gap |
| 6 | FCM token registration (planned only) | Associate a device token with its user (Task 20) | Token refresh | `users/{uid}/fcmTokens` | No | **C + B** | **Deferred.** No messaging SDK or token writer is present; the collection rule is owner-only if registration is added in a later notification phase |
| 7 | Sending a push to a partner | Reach a backgrounded device | A rule matches | Cross-device send | **Yes** | **D** | **Deferred.** No server credential exists, so remote push is not implemented |
| 8 | Pair membership check (FR-064) | One pair must never see another's data | Any partner read | Reads `pairs/{pairId}` | No | **B** | **Firestore Rules** (already in place) |
| 9 | Consent + category authorization | Sharing is per-category and revocable (NFR-002, FR-036) | Any partner read | Reads `sharing/{uid}` + `consents/{uid}` | No | **B** | **Firestore Rules.** Now rejects reads if consent is revoked, not only if a category is cleared |
| 10 | Event history integrity | History must be append-only and trustworthy (NFR-035) | Meaningful state transition | Writes `events` | No | **B** | **Firestore Rules** (already in place) |
| 11 | Device-state synchronisation | Share current state with the authorized partner | Client write | `deviceState`, `location` | No | **B** | **Firestore Rules** (already in place) |

Nothing was classified **D** and then moved to the client. Items 5 and 7 are the
only true **D** items, and both are deferred rather than delegated — see §6.

---

## 3. The rule that makes this safe

> **Authority that a server enforced by executing code is now enforced by
> Firestore Security Rules verifying facts the client cannot forge.**

Applying that test to each replacement:

| Operation | What the client sends | What the client cannot do |
| --- | --- | --- |
| Activate a pair | `status: 'active'` | Write the *other* member's consent. The rule re-reads it, so the client cannot assert agreement that does not exist |
| Publish a code | A code document | Choose a short code, a long-lived code, or list other people's codes |
| Redeem a code | `usedByUserId` | Redeem twice, redeem an expired code, change anything else, or claim to be someone else |
| Notify | A notification document | Write into another user's collection, backdate it, or rewrite its content afterwards |
| Evaluate a rule | Nothing | (Nothing is authorized by evaluation; the result grants no access) |

In every case the *data* comes from the client and the *authorization* comes from
the rules. That is the same division of labour a Cloud Function would have
provided, minus the server.

---

## 4. Notification flow

```
An authorized Firestore state stream
            │
            ▼
   RuleEvaluator (local, pure)          ← device state + the user's own rules
            │
   RuleEvaluationResult                 ← matched / notMatched / insufficientData / stale / disabled / coolingDown
            │
            ▼
   RuleNotificationPlanner (local)      ← honours the user's NotificationPreference
            │
   RuleNotificationPlan                 ← notify / suppressedByPreference / duplicate / …
            │
            ▼
   LocalNotificationService.show()       ← the device raises its own alert
            │
            ▼
   users/{uid}/notifications/{id}        ← owner-written record, so history survives a missed delivery (FR-044)
```

Why this is not a fake server:

- The **trigger** is data the user is already authorized to read. There is no
  cross-user privilege involved.
- The **sink** is the user's own device and the user's own collection. No send to
  another device occurs, so no server credential is required.
- Nothing here can cause a notification to appear on someone else's phone. That
  is exactly the capability that would need a server, and it is deferred rather
  than emulated.

**Honest limitation.** The device raises a notification only while the app is
running and observing. With the app terminated, no rule evaluates, no alert is
raised, and no remote push arrives — because there is no server to send one. The
UI must therefore present *last known state plus its timestamp* rather than
implying the engine is continuously running (`FreshnessIndicator`, FR-061).

---

## 5. Device-state synchronisation

```
Native device APIs
        │
        ▼
DeviceStateSource (platform adapter)      ← reports unsupported, never a fabricated value
        │
        ▼
DeviceState (MetricValue per metric)      ← value + origin + availability + observedAt + freshness
        │
        ▼
Firestore (pair-scoped, category-gated)   ← Rules: consent + sharing category + not paused
        │
        ▼
Authorized partner
        │
        ▼
Local rule engine → interpretation → local notification
```

The client is an *observer* of its own device and never an authority on another
person's data. Unsupported capabilities stay `unsupported`/`unknown`/`stale`; no
platform is forced to return a placeholder (`PLATFORM_CAPABILITIES.md`).

---

## 6. Deferred capabilities

| Capability | Why it cannot exist under Spark | Impact | Where addressed |
| --- | --- | --- | --- |
| Remote push to a partner's device | Requires a trusted sender with an FCM credential | Reassurance alerts only fire while the recipient's app is running | Notification phase; needs Blaze or a non-Google sender |
| Cross-user scheduled retention/deletion | Requires a privileged scheduler acting across users | Retention is policy + lazy, ownership-scoped cleanup | Privacy phase (NFR-031/NFR-032) |
| Server-authoritative rate limiting | Rules cannot throttle | Brute-force is mitigated by code entropy (≥20 chars, ≤1 h) and `list` denial, not by throttling | Documented limitation |

None of these is emulated. A capability the architecture cannot honestly provide
is documented as unavailable rather than simulated.

---

## 7. Cost awareness

The Spark plan has hard quotas. For a standard Firestore database, the current
free quota is 1 GiB stored, 50,000 document reads per day, 20,000 writes per day,
20,000 deletes per day, and 10 GiB outbound transfer per month. Only one free
database is included per project. TTL deletes, backups, PITR, restore, and clone
operations require billing and are not used here. See the official
[Firestore billing documentation](https://firebase.google.com/docs/firestore/pricing)
and [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans).

The design avoids unnecessary work:

- current device state is **one document per (pair, owner)**, overwritten in
  place — never an append-only telemetry stream;
- only **meaningful transitions** become `events`;
- a partner read performs at most a handful of cached `get()` calls
  (pair + sharing + consent);
- `pairingCodes` cannot be `list`-ed, so nothing can scan the collection;
- notifications are one document per alert, not per evaluation;
- rule evaluation and freshness classification are local and free — the whole
  reason to prefer them over a server.

---

## 8. Spark compatibility summary

| Service | Used | Spark-compatible |
| --- | --- | --- |
| Firebase Authentication | Yes — identity only | Yes |
| Cloud Firestore | Yes — data + all authorization | Yes, within the Spark free quota; live usage is unverified because no project is configured |
| Firebase Cloud Messaging | Not currently used; remote push is deferred | N/A |
| Cloud Functions | **No** | Not on Spark |
| Cloud Run / Scheduler / Pub/Sub | **No** | Not on Spark |
| Firebase Extensions | **No** | Several require Functions |

Verification: `test/architecture/spark_only_test.dart` fails the build if a
Functions/Admin dependency, a privileged credential, or a `functions` deploy
target reappears.
