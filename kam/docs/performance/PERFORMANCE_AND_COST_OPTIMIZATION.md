# Performance and Cost Optimization

## Scope and evidence

This is a source audit of the Phase 24 checkout. Runtime profiling, Firestore request counts, Android battery measurements, and before/after benchmarks were unavailable, so this document makes no measured speed, battery, or cost-reduction claims. Phase 23's report is available; Phase 19's security report is available. Phase 20's completion report is absent, so its implementation is inspected in source but its prior validation is not treated as evidence. Phase 21–23 reports are used only for their recorded test limitations.

## Baseline commands

| Check | Result in this environment |
| --- | --- |
| `flutter pub get` | No output for 30 seconds; stopped. BLOCKED. |
| `flutter analyze` | No current completed run. A prior attempt stalled. BLOCKED. |
| `flutter test` | Latest user-provided pre-fix run: 662 passed, 1 privacy test failed (663 total). The test source was subsequently changed; current suite NOT TESTED. |
| `firebase emulators:exec --only firestore "npm --prefix firebase test"` | Failed because `firebase` is not recognized. `npm` is also absent from PATH. BLOCKED. |
| `flutter build apk --debug` | No output for 30 seconds; stopped. BLOCKED. |
| `git diff --check` | No whitespace errors; line-ending conversion warnings only. PASS. |

Historical Phase 19 results (617 Flutter tests and 114 emulator tests) are not current baselines.

## Architecture and source findings

The device path is native collectors → normalized snapshot → local repository → sync coordinator/service → Firestore gateway → partner repository. Sync coalesces changes for 3 seconds, suppresses identical successful payloads, and bounds retry to four attempts with exponential delay (2 seconds base, 30 seconds maximum). Writes are sharing- and pair-scoped. The source has no background worker or periodic heartbeat. Android collectors use native event streams; location updates request a 60-second minimum interval and 100-meter minimum distance, with foreground/lifecycle ownership. No location/performance measurements were captured.

Rule evaluation is local and deterministic. It is driven by rule/state updates plus one bounded timer for the next time boundary (maximum 15 minutes); the timer is canceled on disposal. Interpretation transitions feed history/notification logic, not a remote model call. Dashboard relative-time labels use one minute timer per mounted dashboard and cancel it on dispose. This was source-inspected, not profiled.

### Firestore operation inventory

Frequency below is trigger-based because no runtime counters exist.

| Path / data | Operation and caller | Trigger / expected frequency | Necessary / optimization and security notes |
| --- | --- | --- | --- |
| `pairingCodes/{code}` | WRITE set; pairing repository | User creates invite | User action; retain expiry/authorization semantics. |
| `pairingCodes/{code}`, `pairs/{id}` | TRANSACTION read code, write code and pair | Invite redemption | Atomic one-time redemption; do not remove transaction reads. |
| `pairs/{id}/consents/{uid}` | TRANSACTION read then set consent | User confirms consent | One user action; required to prevent duplicate/invalid consent. |
| `pairs/{id}` and `pairs/{id}/sharing/{uid}` | TRANSACTION reads pair and both consent docs; updates pair and sharing docs | Activation after both consents | Authorization-sensitive; retain reads and atomic activation. |
| `pairs` membership query, `pairs/{id}/members/{uid}` | READ profile and active-pair query; merge WRITE member copy | Profile update / pairing setup | Profile update only. The exact-two-user constraint bounds results; authorization and partner-approved copy must remain. |
| `pairs` membership query | LISTENER query (`arrayContains memberIds`) | Pair provider while signed in | Shared provider-level stream, not per widget; disposed with auth/provider scope. |
| `pairs/{id}/members/{uid}` | LISTENER document | Partner display name needed | Pair-scoped; provider-owned. |
| `pairs/{id}/sharing/{uid}` | LISTENER and merge WRITE | Sharing screen/state; user changes settings | One listener per relevant provider; writes only on user action. Sharing state is security-sensitive. |
| `pairs/{id}/deviceStates/{uid}` and location companion | WRITE set/delete and LISTENER | Meaningful sync/retraction; partner view | Two pair-scoped state streams. Sync service coalesces and deduplicates payloads. Retain freshness/version fields. |
| `users/{uid}/rules` | QUERY read; document READ; set/update/delete WRITE | Rule screen load or user edit/delete | Read is owner-scoped and on demand; deletion verifies document first. No realtime rule listener. Pair filter occurs locally after owner-only query. |
| `pairs/{id}/events` | LISTENER query ordered by `recordedAt`, optional category filter, limit ≤100 | History view for active category | Provider family now auto-disposes when no consumer watches that filter. Pair authorization and owner-scoped local merge remain. |
| `pairs/{id}/events/{stableId}` | WRITE set; user-visible charging/network/rule transition | Meaningful transition only | Append-only deterministic ID; server timestamp. Duplicate retry can still make a denied create-only write attempt; keep rule-level create-only boundary. |
| `pairs/{id}/events` | QUERY read limit 200 + BATCH delete | Explicit owner history clear, repeated until empty | Destructive user action; owner-scoped. Page size bounds each batch. |
| `users/{uid}` | READ or LISTENER; transaction read/WRITE; profile update WRITE then read-back | Sign-in/profile load or explicit profile mutation | Profile listener is auth-scoped. Read-back supplies stored timestamps; pair profile propagation happens only on edit. |
| `users/{uid}/settings/preferences` | READ and merge WRITE | Settings load or explicit preference change | User action; keep settings private and owner-scoped. |

No widget-level Firestore call, broad raw-observation write, or heartbeat was found in the audited repositories/providers. The list covers code paths found by source search, not every SDK-internal retry or cache read.

### Queries and indexes

The Firestore index manifest includes pair membership plus status; events by category/recorded time; device/occurred time; owner/occurred time; and several interpretation/rule/notification composites. The current history listener filters by `category` and sorts by `recordedAt`; its manifest composite supports that query. Unfiltered history sorts on `recordedAt` and can use automatic single-field indexing. Rules query owner subcollection by `pairId`; profile pair lookup is membership plus status. No query result-size or billed-read measurement is available.

## Optimization applied

`historyEventsProvider` is a parameterized stream keyed by category. Each active category represents a distinct history query. It was changed to `StreamProvider.autoDispose.family`, allowing the query subscription to end when the last consumer leaves that category. The UI still watches the selected category and the dashboard preview still watches the unfiltered category; query contents, limits, authorization, cache merge, and ordering are unchanged. This is a lifecycle correction based on provider ownership, not a measured savings claim. Riverpod recommends auto-disposal for family providers whose parameters change to avoid retaining unused states ([Riverpod families](https://riverpod.dev/docs/concepts2/family)).

## Areas reviewed, no speculative changes

- **Reads/listeners:** membership, profile, sharing, paired state, and history listeners are provider/repository-owned. History is the only parameterized live query found, and now has consumer-scoped disposal.
- **Writes/change detection:** state sync coalesces and signature-deduplicates successful payloads. History records meaningful transitions rather than every observation. No arbitrary battery/location threshold was introduced.
- **Lifecycle/background:** monitoring stops on lifecycle pause and cancels native subscriptions. No background job, heartbeat, or polling loop was found. Android force-stop/Doze behavior remains platform-limited and requires device testing.
- **Rule/notification work:** evaluation is input/transition-driven with bounded time reevaluation and disposal. Existing deduplication/cooldown behavior was preserved.
- **Cache:** existing local history is bounded to 500 records and 180 days; displayed page is capped at 100. Sensitive local-data cleanup remains the existing mechanism. No additional cache was added.
- **Startup/lazy loading/UI:** no startup trace, rebuild profile, or allocation profile could be captured. No restructuring based on guesses.
- **Potential follow-up:** `PlatformDeviceStateProvider.watchState()` first calls `getCurrentState()` and then starts collectors whose `start()` methods refresh again. This can duplicate initial native reads on monitoring start/resume. Changing it requires counters and collector/lifecycle regression coverage, especially for charging-duration session reset and location permission/freshness behavior; no change was made without runnable Flutter tests.

## Measurements and limitations

Before/after CPU, frame, memory, location request, battery, Firestore read/write, and listener counts: NOT MEASURED. Flutter test/analyzer/build and Firestore emulator commands: blocked as shown in the baseline table. Physical Android, two-user, offline/revocation, and Doze testing: not available. Do not interpret the source-level listener disposal as a quantified Firebase cost reduction.
