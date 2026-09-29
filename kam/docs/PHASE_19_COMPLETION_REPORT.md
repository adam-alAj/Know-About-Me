# Phase 19 — Security, Authorization & Firebase Security Rules

Completion report. The authoritative model lives in
[`security/SECURITY_AND_AUTHORIZATION.md`](security/SECURITY_AND_AUTHORIZATION.md).

---

## 1. What was audited

Firebase initialization, Firebase Auth, all Firestore repositories and models,
`firestore.rules`, `firestore.indexes.json`, pairing/codes, consent and sharing,
device-state synchronization, rule definitions, interpretations, notifications,
history/events, local persistence, the router guard, lifecycle handling,
environment/build configuration, and both the Dart and emulator test suites.

## 2. Findings and severity

| Sev | Finding | Impact |
| --- | --- | --- |
| **High** | `ruleValid()` referenced `request.resource.data.type`/`category`, which a rule document does not contain. Every rule create/update was denied by a rules **evaluation error**; 5 emulator tests were failing before the fix. | The Phase 14 rule feature was non-functional in production. Fail-closed, but a real break — and proof the rules were never validated against the client schema. |
| **Medium** | `devices/{deviceId}` had no field whitelist, no type/length checks, mutable `ownerUserId`/`deviceId`, and accepted client-supplied `lastSeenAt`. | A modified client could store arbitrary (including hardware-identifying) data in a pair-readable document and forge device presence timestamps. |
| **Medium** | `interpretations/{id}` create had no field whitelist or bounds. | Unbounded/extra fields could be stored in a partner-readable document. |
| **Medium** | The local history cache is device-wide and was rendered without an owner scope; protected local state was not cleared on sign-out. | On a shared device, a second account could see the first account's cached timeline (NFR-004). |
| **Low** | `notifications/{id}` create lacked a closed field set. | Arbitrary fields could be appended to the owner's own (private) notification records. |
| **Low** | `sharing` updates required no server timestamp and allowed extra fields. | Sharing changes could be backdated and the authorization document padded. |
| **Low** | Deployed `firestore.indexes.json` was missing `pairs(memberIds CONTAINS, status)`; the `firebase/` copy had drifted. | The partner-visible profile-sync query would fail with `failed-precondition` in a deployed project. |
| **Info** | `users/{uid}` update contained an unreachable `activatedAt`/`status` branch (the key whitelist forbids those fields). | Dead, misleading logic; removed. |
| **Info** | `firebase_options.dart` embeds Firebase client API keys. | Client-safe identifiers, not privileged credentials (documented in FIREBASE_SECURITY §7); left as-is. |
| **Info** | No server-side rate limiting; pairing `get` returns the full code document. | Unavoidable under Spark; documented as limitations rather than "fixed". |

No **Critical** finding: no path was found that lets an authenticated user read or
write another pair's protected data, or forge consent/membership.

## 3. Fixes implemented

**Firestore Security Rules (`firestore.rules`, mirrored at `firebase/firestore.rules`)**

- Removed the erroneous `type`/`category` block from `ruleValid()`.
- `devices/{deviceId}`: closed field set, `ownerUserId`/`deviceId`/`platform`
  immutable on update, bounded `lastSeenAt`, extra fields rejected.
- `interpretations/{id}`: closed field set, bounded message/ruleId/basis,
  ranged `probabilityPercent`, typed `producedAt`.
- `notifications/{id}`: closed field set; bounded `pairId`/`ruleId`.
- `sharing/{uid}`: closed field set and `updatedAt == request.time`.
- `users/{uid}`: removed the unreachable `activatedAt`/`status` branch.

**Client**

- `LocalStorageKeys` + `SensitiveLocalData` (`lib/core/storage/`) centralize the
  app-private cache keys and clear the protected subset on session end; all six
  stores now reference the shared keys.
- `AuthController` clears protected local state on explicit sign-out **and** when
  the identity stream reports the session ended elsewhere.
- `HistoryRepository.page` accepts `ownerUserId`; `historyEventsProvider` resolves
  the signed-in uid and scopes local reads to it (and returns nothing when there
  is no identity).
- `firestore.indexes.json` (deployed path) synced with the complete index set.

## 4. Tests

| Suite | Command | Result |
| --- | --- | --- |
| Firestore Security Rules (emulator) | `firebase emulators:exec --only firestore "npm --prefix firebase test"` | **114 / 114 pass** (was 101, with 5 failing) |
| Flutter analyze | `flutter analyze` | **No issues found** |
| Flutter tests | `flutter test` | **617 / 617 pass** |

New emulator tests cover forged privilege fields, sharing timestamp/field
hardening, paused writes, device-record ownership, interpretation and
notification field sets, the two-person invariant (three members), and history
cross-pair/ended-pair access. New Dart tests cover the sign-out cleaner, local
history owner-scoping, and both session-end cleanup paths.

## 5. Spark compatibility

No Cloud Functions, Cloud Run, Scheduler, Pub/Sub, Extensions, Admin SDK or
service account was introduced. `test/architecture/spark_only_test.dart` continues
to pass, and `firebase.json` still declares no billing-required deploy target.

## 6. Known limitations (unchanged / documented)

Server-side rate limiting, global pair-id uniqueness, category-retraction of
already-recorded history, instant offline revocation awareness, App Check, and
scheduled cross-user cleanup. See
[`security/SECURITY_AND_AUTHORIZATION.md`](security/SECURITY_AND_AUTHORIZATION.md) §19.

## 7. Validation commands run

```bash
cd kam
flutter analyze
flutter test
firebase emulators:exec --only firestore "npm --prefix firebase test"
dart format --output=none --set-exit-if-changed lib test   # see note
```

> **Note on `dart format`.** The repository was **already** not format-clean
> before Phase 19 (78 files change under `dart format`, verified against `HEAD`).
> No whole-repo reformat was performed, to keep this phase's diff reviewable. All
> new Phase 19 files are format-clean; the two edited files that `dart format`
> would change were already unformatted at `HEAD`.

## 8. Status

```text
COMPLETE
```
