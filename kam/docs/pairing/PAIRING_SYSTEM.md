# Pairing system (Phase 5)

## Lifecycle

```text
pairing code: created -> redeemed (single use), or cancelled / expired
pair: pending -> active (only with both member consent records)
pair: pending -> revoked (a member rejects); active -> revoked / disconnected
```

The invitation owner generates a 26-character code using Dart `Random.secure()` from a 32-symbol alphabet (about 130 bits). It expires after 20 minutes. The code itself is the `pairingCodes/{code}` document key; code documents cannot be listed, and only a known, live, unused key can be read. Redemption atomically marks it used and creates a pending pair. The code is a discovery capability only and never authorizes device data.

## Data model

```text
pairingCodes/{code}
  createdByUserId, status (created/consumed/cancelled), createdAt, expiresAt,
  revoked, usedByUserId, usedAt
pairs/{pairId}
  memberIds[2], requestedBy, status, invitationCode, schemaVersion,
  createdAt, updatedAt, activatedAt?, endedAt?
pairs/{pairId}/consents/{uid}
  userId, pairId, granted, categories, grantedAt, updatedAt
pairs/{pairId}/sharing/{uid}
  userId, pairId, paused, categories, updatedAt
```

Pair documents contain only account IDs and lifecycle metadata. Future state belongs in pair-scoped subcollections; current pairing UI does not write telemetry. The `sharing` records start with no enabled categories.

## Authorization and consent

Firestore rules require authentication, a consumed invitation for pair creation, exactly two distinct members including the caller, per-user consent writes, and both consent documents before activation. Consent decisions cannot be rewritten in place; a user can remove their own consent, immediately stopping shared reads. Pair membership and invitation identity are immutable. Active reads require an active pair and current grants; either member can terminate the pair. A denied/withdrawn standing grant immediately blocks reads even before a status update is observed. Pair reads and listeners are scoped to member IDs; invitation collection listing is denied.

The client is not an authority: repository checks improve feedback, while rules make access decisions. Invitation expiry uses Firestore `request.time` in rules. Expired documents may remain stored; no scheduled cleanup runs.

## Spark limitations and security review

No Cloud Functions or trusted backend are present. Random-code quality depends on the shipped client using a CSPRNG; rules can check length, format, single use and lifetime, but cannot prove the client generated entropy. There is no server-side/IP-based rate limit or brute-force counter. A 130-bit random code and short lifetime make guessing impractical, not impossible; the app must not claim brute-force immunity. Known-code lookup reveals minimal invitation metadata (creator UID) to the authenticated redeemer, and no profile data is returned by that document.

The Spark rules can verify two independent consent records, but cannot provide an untrusted-client-proof global uniqueness index for user pairs. Client transaction retries are idempotent for one pair ID, but a modified client could try a second pair ID. This limitation needs a trusted backend or canonical pair key enforceable by rules before claiming strict duplicate-pair prevention. Rules do prevent forged activation, injected third members, changes to membership, invitation replay, and post-disconnect device reads. Rule emulator tests remain the authorization evidence; Flutter tests cannot substitute for them.

No two-account/device acceptance run or real Firebase deployment was available in this workspace. No device metrics, location, notifications, or monitoring were added.
