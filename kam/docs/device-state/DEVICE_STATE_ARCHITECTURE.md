# Device State Architecture (Phase 6)

```text
Native APIs (battery + network implemented; other collectors deferred)
    ↓
PlatformDeviceStateAdapter
    ↓
DeviceStateProvider
    ↓
DeviceStateSnapshot
    ↓
LocalDeviceStateRepository
    ↓
Riverpod/application state
    ↓
Firestore synchronization (Phase 11; not implemented)
```

The Android/iOS boundary is `PlatformDeviceStateAdapter`; capability reads are
isolated so one failure cannot discard other readings. Battery and charging use
a dedicated event-driven native bridge and collector. Network transport,
reachability, and online/offline observations use an independent event-driven
bridge and collector. Display state, activity signals, application lifecycle
and evidence-based availability use a third independent collector with a
single persisted timestamp (Phase 9, see
[`ACTIVITY_AVAILABILITY.md`](ACTIVITY_AVAILABILITY.md)). Foreground location,
permission/service state, the user-configured home and distance-based presence
use a fourth independent collector, which never auto-prompts for permission and
keeps home coordinates out of the snapshot (Phase 10, see
[`LOCATION_HOME_DISTANCE.md`](LOCATION_HOME_DISTANCE.md)). All typed values are
part of the local snapshot; later phases add remaining capability collectors. The legacy dashboard model remains
available for existing presentation consumers.
The application continues using Riverpod and the existing legacy `DeviceState`
model for current presentation consumers.

`DeviceStateProvider` supports one-shot collection and a best-effort stream.
`DeviceMonitoringController` exposes start, stop, and collect-now commands.
`DeviceMonitoringLifecycle` starts observation at launch/resume and stops it
when Flutter reports inactive, paused, or detached. It also pushes each
lifecycle transition into the activity collector, where an observed
transition is a supported signal while an initial report only establishes the
current phase. No periodic scheduler or
terminated-app execution is promised.

## Local and partner data

`DeviceStateRepository` exposes only local state. `PartnerDeviceState` is a
distinct wrapper for a future authorized remote snapshot. A snapshot assembled
locally is never used as partner state. Current authenticated user identity is
attached when available; local collection can still happen without an active
pair. This phase has no write/sync path. Phase 11 must authenticate the writer,
derive owner identity from auth, require active pair consent, and rely on tested
Firestore Security Rules for authorization.

## Efficiency and privacy

There is no polling loop, high-frequency telemetry, background location request,
Firestore write, or background service. Location is read once per refresh while
the app is in the foreground and monitoring is active, and the native bridges
throttle updates (Android 60 s/100 m, iOS `distanceFilter` 100 m). The local
repository caches one snapshot and refreshes only when explicitly asked. Logs
include capability names and error types, never values, user IDs, tokens, pairing
codes, or precise location — the location collector and both native bridges log
no coordinates at all.

The app-generated opaque device ID is 128 random bits encoded as 32 lowercase
hex characters and persisted in app-private preferences. It contains no
hardware data and is not a credential. Reinstall clears app-private
preferences, so reinstall generates a new ID; device replacement also gets a
new ID. Account/pair ownership remains the authenticated user and Firestore
Rules, never this ID.
