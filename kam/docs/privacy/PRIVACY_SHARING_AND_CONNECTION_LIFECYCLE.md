# Privacy, Sharing, and Connection Lifecycle

## Architecture and consent

The authenticated account owns one pair-scoped sharing document at
`pairs/{pairId}/sharing/{userId}`. Pair membership and active lifecycle status
are established by mutual consent. Each member independently chooses categories
in that document. A missing or unreadable document means no sharing. Pair
acceptance never enables a category automatically.

The existing `SharingCategory` enum is the supported category vocabulary:
battery, charging, network, location, distance from home, activity indicators,
and rule interpretations. All categories start disabled. There is no distinct
alerts switch or device-availability category yet; alerts are local and depend
on authorized rule inputs, while availability metadata is exposed only when a
device-state category is shared.

## Effective sharing and synchronization

Firestore Rules are the server authorization boundary. The owner can write only
their own pair-scoped setting and state. Partner reads require active pair
membership, mutual consent, an unpaused owner sharing document, and a matching
enabled category. The device-state sanitizer is the client-side data minimizer:
it includes enabled fields and clears disabled ones. Location is separately
gated and removed when disabled; distance and home presence are separately
gated. Exact home coordinates are not synchronized.

The `authorizedPartnerDeviceStateProvider` is a central client projection used
by dashboards, rule evaluation, and the state inspection view. It returns no
partner state while sharing is paused, absent, unreadable, empty, or represented
only by a cache snapshot. It also strips fields for categories the partner has
disabled. This promptly invalidates the in-memory inputs used by rule evaluation
and local alerts; Firestore Rules independently reject subsequent unauthorized
reads.

OS permission and sharing permission remain separate. A category switch does
not grant a device permission, and a device permission does not authorize
sharing. Collectors report unsupported, denied, unavailable, and stale states
where the platform supplies that information. Location visibility also
requires location to be explicitly selected.

## Pause, resume, revoke, and disconnect

Pause is a reversible `paused: true` setting on the sharing document. It keeps
the pair active but withholds every category. The selected category list is
retained; resuming restores only that existing selection. A new local snapshot
is sent through the sanitizer after settings change, so retractions or the
latest valid state are queued by the existing sync service.

Disconnect and revoke are terminal pair status updates (`disconnected` and
`revoked`). Both stop authorized streams when the pair membership provider
updates, which in turn removes rule inputs and dependent local alerts. Revoke
communicates permanent consent withdrawal and requires a new pair for future
sharing. A disconnected pair cannot be reactivated by this client flow.

## Location and home privacy

The location sharing switch is independent of the OS location permission. When
disabled, the location document is deleted by the synchronization pipeline and
the partner projection removes any already cached location. When enabled, the
last valid fix may include coordinates and its observation time; current
permission, service state, capability, and freshness still constrain what the
collector can produce. Location history is not generated. The distance/home
switch controls derived distance and home-presence fields. Home coordinates are
owner-private and are never part of the partner payload. The current Firestore
contract stores derived distance in the location document, so the partner can
read that document only when Location is enabled too. Enabling only
Home-and-distance does not publish a readable distance value. When Location is
also enabled, current/last location coordinates are shared as described above;
users who want derived distance without location coordinates need a future
separate distance document and matching rules.

## History and notifications

History records only its existing bounded event taxonomy, subject to the
author's sharing state and category. It does not store exact coordinates or raw
device snapshots. Local notifications are generated on the device from
authorized partner state and existing notification preferences. Their visible
content remains generic; no server push infrastructure is used. Remote history
retention remains bounded only by user-initiated cleanup because cross-user or
scheduled deletion would require trusted server infrastructure unavailable on
the Spark-only plan.

## Offline behavior and cache

Firestore client writes are queued while offline. An offline switch-off updates
the local sharing stream and the sync coordinator immediately; cache-only
authorization is treated as no permission for partner reads and publication.
An offline switch-on does not resume publication until the new setting is
confirmed by a server snapshot. On reconnect the sharing document is reconciled
first, then the coordinator uses a current local snapshot to apply the
sanitizer. Remote revocation takes effect when the device next receives the
updated membership/sharing state; until then the app cannot know that the server
revoked it, but Firestore Rules enforce the remote boundary on each request.

Firestore local persistence may retain SDK-managed cached documents on device.
The app does not claim secure erasure of those internal caches. The central
projection prevents cache-only data from being presented or evaluated as
authorized. Account deletion is not implemented as a complete server-side
deletion workflow; pair event retention and deletion limitations are documented
in the history guide.

## Lifecycle and platform limits

Pair documents distinguish pending, active, revoked, and disconnected. A
temporary pause is represented by the per-owner sharing document rather than
changing pair status, so each partner can pause independently. Lifecycle model
transitions are also defined in `PairLifecycleState`; the Firestore pair status
is the server authority.

Background collection, location permissions, and screen/activity capabilities
vary by Android/iOS version and user settings. Lack of network connectivity is
not treated as proof that a device is powered off. The app uses bounded
Firestore listeners and writes, and this phase adds no Cloud Functions, Cloud
Run, Pub/Sub, Scheduler, Admin SDK, or paid service.

## Security Rules and known boundary

Both `firestore.rules` and `firebase/firestore.rules` enforce membership,
consent, pair lifecycle, per-owner sharing, and category checks for device
state, location, events, and history. They are intended to remain identical.
Rules can prevent future reads and writes; they cannot remotely erase a value
already copied to a partner device. Client cache invalidation is best effort on
the recipient device, while authorization checks remain server-side.

The category vocabulary does not yet expose independent screen state, alerts,
or device availability switches. Activity and screen state share one category.
Exact live location is currently part of the location payload when the owner
explicitly enables location; users should leave that category off if they only
intend to share derived home distance. A future schema could separate those
outputs more strictly.
