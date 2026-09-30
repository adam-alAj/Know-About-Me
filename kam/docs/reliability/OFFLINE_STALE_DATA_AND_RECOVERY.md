# Offline, Stale Data and Recovery (Phase 20)

## 1. Architecture

Phase 20 extends the existing Phase 11 device state pipeline rather than adding a second cache or synchronization service. Platform collectors create local observations; `DeviceStateSyncCoordinator` holds the active `PartnerScope`, the last snapshot and the latest usable local sharing decision; `DeviceStateSyncService` sanitizes, compares, coalesces and publishes through `FirestoreDeviceStateSyncGateway`. `FirestorePartnerDeviceStateRepository` merges the partner's device-state and location documents, preserving Firestore cache metadata. Pair membership, sharing, auth, rules, notification and history providers continue to own their existing responsibilities.

The relevant code is under `lib/core/connectivity`, `lib/core/freshness`, `lib/features/device_state`, `lib/features/rules`, `lib/features/notifications` and `lib/features/history`. Firestore Security Rules remain the only backend authorization boundary. The Phase 19 mechanisms in `docs/security/SECURITY_AND_AUTHORIZATION.md` remain authoritative.

## 2. Connectivity model

`ConnectivityState` is `online`, `offline` or `unknown`. `ConnectionEvidence` derives it from Firestore snapshot metadata, locally pending writes, and a known network failure. A server-confirmed membership or partner-state document is evidence of online access; a cache-only document or queued write is evidence of offline access. No document at startup means `unknown`, not offline. This is evidence about backend reachability, never the partner phone's power state or the user's authorization.

The app does not perform a separate network probe. Consequently, until it receives a server snapshot or an operation result, it may honestly show `unknown`. `SynchronizationState` separately represents `idle`, `syncing`, `pending`, `failed` and `blocked`. `RecoveryState` remembers whether a previously offline session is catching up, recovered, or blocked. The reusable connection banner/indicator only surfaces supported states and does not expose Firebase details.

## 3. Synchronization model

Firestore's snapshot metadata is retained by repositories (`isFromCache`, and sharing/membership `hasPendingWrites`). The local state publisher exposes run outcomes and in-flight work. Transient failure, permanent refusal and backend reachability are not collapsed into one boolean. No application code configures a custom Firestore cache or replaces the SDK cache.

The SDK handles its own pending Firestore writes. The device-state service has a separate in-memory latest-snapshot slot for app-level publication requests; it is not a general durable queue. On an app resume or fresh local observation, the latest snapshot can be requested again. Firestore Rules re-evaluate queued writes against current server state when they reach the backend.

## 4. Freshness model

`FreshnessPolicy` in `lib/core/freshness/data_freshness.dart` is the shared classifier. The standard policy marks data fresh through 2 minutes, recent through 15 minutes, then stale. The slower policy is fresh through 15 minutes and recent through 2 hours. Location is fresh through 5 minutes and recent through 30 minutes. Boundary comparisons are inclusive. Missing timestamps are `unknown`; negative ages (clock skew) are treated as fresh by the existing policy and should be interpreted with the timestamp caveat below.

Freshness is based on observation time, not on Firestore receipt time, app restart time, or synchronization time. Partner state and location expose freshness helpers, and dashboard/cards render age and stale/unknown labels. Stale values remain useful as explicitly last-known values. They do not imply a current condition. An unavailable metric is distinct from stale or unknown. Capability availability separately represents unsupported, permission-denied, service-disabled and error cases; presentation maps those to neutral user-facing wording.

## 5. Timestamp semantics

For synchronized device state, `observedAt` is the device's observation time. Firestore `updatedAt` is assigned with `FieldValue.serverTimestamp()` when the server accepts the write and is parsed as `synchronizedAt`. Neither overwrites the other. The partner envelope also has `receivedAt`, which is the receiving client's clock when a snapshot arrives; it is not an observation or server synchronization timestamp.

For history, `occurredAt` describes the event/evaluation time, optional `observedAt` identifies the underlying device observation, and `recordedAt` is assigned by Firestore on creation. The local history copy keeps its original fields and is owner-filtered by the provider. Synchronization does not rewrite event occurrence times.

## 6. Firestore offline behavior

`FirebaseBootstrap` initializes Firebase and emulator routing; it does not explicitly call a persistence configuration API. Therefore the project relies on the Firestore SDK's platform defaults. On Android and Apple platforms the SDK enables offline persistence by default; web persistence is not enabled by this app and has different SDK defaults. No custom cache has been added. Snapshot metadata is carried into domain envelopes where the UI and connection evidence need it. Firestore local cache contents are not authorization proof and may outlive the remote state they represent until a server request is possible.

Firestore queues writes according to SDK behavior while offline. A write's eventual success is not guaranteed: current rules can reject it on reconnection. The app must show the outcome and must not repeat permanent permission or validation failures. This is not a custom retry queue.

## 7. Cached partner state

`RemoteDeviceState` carries the partner's observations, their original times, `synchronizedAt`, `receivedAt`, schema/version information, and `isFromCache`. The remote parser validates ownership, schema, types and ranges; absent metrics remain unavailable. `authorizedPartnerDeviceStateProvider` filters by the best locally available sharing snapshot: disabled categories and paused sharing are withheld; a cache-only sharing record is treated as last-known state and does not by itself erase useful cached partner data. That policy is necessarily limited while disconnected: a client cannot know about a remote revocation until it reconnects. Cached data is explicitly marked and aged. A newer synchronization of an old observation does not make it fresh.

## 8. Pending operations

Phase 19 Firestore writes remain governed by Security Rules on the server. The device-state service only publishes its own state under the active resolved pair scope. Changing pair scope resets signatures and version-loading state. Stopping the coordinator clears its scope, sharing and remembered snapshot. A local privacy decision with `hasPendingWrites` is applied immediately; a cache-only sharing value without a local pending write is treated as unknown and does not trigger a false retraction.

This repository does not add a generic operation queue, nor does it reconstruct one-time pairing or consent operations. Pairing and lifecycle writes retain their existing operation-specific repository and rules behavior. Permanent `permission-denied`, `unauthenticated`, malformed and precondition failures are classified as blocked. Transient failures are eligible for bounded retries.

## 9. Coalescing

`DeviceStateSyncService.requestPublish` replaces a pending request with the newest snapshot and debounces it for three seconds. If a write is running, only the latest subsequent request is retained. The service sanitizes each document and compares a canonical signature that excludes volatile version/sync fields, so unchanged data is not written again. Battery/network/activity state is published as current state documents, not as every intermediate sample. Location is a separate document and is only included when shared and usable. The service does not replay a trail of GPS samples.

The coalescer and retry state are in memory. A process termination does not promise that this app-level latest snapshot will survive; a later collector/resume trigger regenerates current state. Firestore itself may still hold SDK-managed pending writes.

## 10. Idempotency

History events use deterministic document IDs and create-only Security Rules, making a retried event write unable to create duplicate timeline entries. A denied update of an already-existing deterministic event ID is treated as an already-recorded event by `FirestoreHistoryRepository`; other failures propagate. Local history also ignores an existing event ID. Rule notification delivery keys combine rule/version/evaluation identity and the local service suppresses repeated keys in the process. Notification deduplication is process-local, not durable across app restarts; OS request identifiers also replace matching requests on supported platforms.

## 11. Reconnect flow

Connectivity restoration is observed through Firestore metadata or the result of an attempted write, not a reachability poll. Firestore resumes listeners and handles its SDK queue. The app re-derives connection state, then current authentication and pair/sharing providers continue to drive scope and authorization. The existing coordinator only publishes under an active scope and current usable sharing state; changed content is synchronized, unchanged content is skipped. Remote listeners supply refreshed state and metadata. Freshness is calculated again from the partner's original observation time. The rule evaluation provider consumes authorized refreshed state, and the notification planner then applies the existing transition, preferences, permission and cooldown checks.

Reconnect is not a grant of authorization. A local recovery indicator can report what the app observed, but only Firestore rules decide whether backend reads/writes are currently authorized. A successful connection document does not prove every document is current.

## 12. Authorization revalidation and remote revocation

The pair, consent, pause, membership, owner and category gates described in Phase 19 are not weakened. When connectivity returns, Firestore Rules evaluate each queued request against current server documents. A denied queued write is classified as blocked and is not placed in the transient retry loop. The auth/pair/sharing streams continue to drive providers; pair termination removes the active scope, stops partner-state access and resets publication bookkeeping. Session cleanup continues through `SensitiveLocalData`.

A fully offline device cannot instantly learn that a remote pair was revoked. Until a server response is possible it may retain previously cached partner state, presented as cache-served and with its original age. On reconnection, the next authorized read/write is checked; denied reads stop the listener/provider path and denied pending writes are not blindly retried. No client-only mechanism can eliminate that offline knowledge gap.

## 13. Offline privacy changes

A local sharing write carries Firestore `hasPendingWrites`, and `PairSharingState.isConfirmed` treats that local pending decision as the user's current choice. The coordinator applies it immediately to the locally held snapshot: disabling a category removes its fields from outgoing state, and disabling all sharing/pausing retracts already-published documents when the request is processed. This means the local app does not continue to enqueue new disallowed location content while waiting for server acknowledgement. Security Rules remain responsible for whether queued writes are accepted. A cache-only old sharing snapshot with no pending local decision is not treated as a new user choice.

## 14. Rule evaluation with stale data

The existing deterministic Rule Engine consumes the authorized partner-state snapshot. `RuleEvaluationService` passes the state's observation freshness and per-metric observation times to evaluation/interpretation. The evaluator marks inputs outside their metric freshness policy stale; rules that require fresh input become indeterminate (`staleData`), while explicit `allowStaleData` rules may match but the result remains labelled stale. Unknown, unavailable, unsupported and permission-denied inputs remain indeterminate, not false and not matched. Location rules use the location freshness policy. There is no separate Phase 20 rule engine or cache.

## 15. Notification behavior

The existing notification planner only accepts eligible new matched transitions after evaluation, applies preferences and cooldown, and uses deterministic evaluation fingerprints where available. Loading a cache or reattaching a listener does not itself mean a new transition: repeated matches remain `stayedMatched`; stale/unknown inputs do not become current matches. On reconnect, rules first consume the refreshed authorized state; only a genuinely eligible new transition can produce a local notification. Notifications are local-only under the Spark architecture. Process-local fingerprints do not provide durable cross-restart history, so a restart-level guarantee is limited by the current notification design.

## 16. Lifecycle recovery

`DeviceMonitoringLifecycle` restarts monitoring and invokes a resume hook on foreground resume; it stops observation on other lifecycle phases. The controller clears its subscription handle before awaiting cancellation, preventing a rapid inactive/resumed transition from leaving a stopped monitor that appears active. Resume refreshes derived connection evidence and reasserts the latest snapshot; it does not claim background monitoring continued. Platform collectors remain best effort and platform capability restrictions are documented in `docs/platform/PLATFORM_CAPABILITIES.md` and `docs/device-state/DEVICE_STATE_ARCHITECTURE.md`.

## 17. Listener recovery

`FirestorePartnerDeviceStateRepository` creates one stream per state document and one per location document for an active partner scope. It waits for both initial snapshots, merges them, forwards errors, and cancels both subscriptions when its output is cancelled. Provider scope changes, sign-out and pair revocation remove the authorized scope and dispose the prior stream. Resume invalidates derived connection status rather than rebuilding subscriptions directly. Sharing changes filter partner state in the existing projection; no aggressive polling loop is introduced.

## 18. Retry behavior

Application-level device-state retry is bounded to four retry attempts after the initial failed attempt, with exponential delays beginning at 2 seconds and capped at 30 seconds. The failed state is not recorded as published; retry uses the latest request, so newer state supersedes an older failed snapshot. A blocked authorization/validation result stops immediately. After exhausting transient retries, the service waits for a later local change or resume/reconnect trigger. It does not build distributed retry infrastructure. Unclassified failure codes receive the same bounded budget but are not treated as proof that connectivity is offline.

## 19. Local cache security

Phase 19's `SensitiveLocalData` and `LocalStorageKeys` remain the centralized cleanup mechanism. Sign-out, identity-session loss and pair scope changes retain their existing cleanup/reset behavior. Local history is owner-scoped on read and cleared on session end. Cache freshness is separate from authorization. Location/home data and notification state retain their existing feature-specific storage rules; no new sensitive persistent cache was introduced by Phase 20.

## 20. Firebase Spark constraints

Firestore remains the backend. The changes add no Functions, Cloud Run, Scheduler, Pub/Sub, Admin SDK, service account, extension or paid Google service. There is no trusted server to schedule retries, send remote alerts, globally clean history or push revocation to offline clients. Security Rules remain the backend enforcement point.

## 21. Testing

Phase 20 adds unit/widget coverage for freshness and connection state, lifecycle restart without listener duplication, latest-state coalescing, observation timestamp preservation, bounded transient retry, non-retry of permission denial, immediate local sharing changes, stale notification suppression, and cache metadata presentation. The existing emulator suite covers the security rules and has added reconnect-related rules cases; emulator tests cannot simulate real device radio or lifecycle behavior. Two-account device acceptance also requires physical/emulated clients and was not automated here.

Validation command for rules remains:

```powershell
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

## 22. Known limitations

- A fully offline client cannot instantly know that a remote pair was revoked; previously cached data may remain locally available until connectivity returns. The UI must preserve cache age and must not treat cache as current authorization.
- `unknown` is possible until Firestore provides usable connectivity evidence; no separate connectivity plugin/probe is installed.
- Firestore cache behavior is SDK/platform-specific because the app has no explicit persistence override. Web persistence is not configured by this app.
- App-level coalescing/retry memory is not durable across process death; foreground observation or a later trigger is needed to publish the latest local state.
- Rule/notification evaluation is foreground/process scoped. There is no promise of continuous background monitoring, and notification idempotency is process-local.
- No manual two-account radio/revocation/lifecycle test was available in this run.
