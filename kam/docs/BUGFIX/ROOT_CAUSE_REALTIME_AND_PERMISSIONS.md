# Root cause: realtime state and Android permissions

**Status: SOURCE FIXED; VALIDATION INCOMPLETE**  
**Audit date:** 2026-10-02

## Symptoms and confirmed cause

The dashboard's pull-to-refresh awaited `DeviceMonitoringController.collectNow()`,
which returned a newly collected Android snapshot, but discarded that value. It
then called `DeviceStateSyncCoordinator.reassertLatest()`. That method only
publishes the coordinator's previously remembered snapshot. The Firestore state
could therefore remain old even though a fresh native read had just completed.
This is a source-level confirmed refresh defect. No production device or backend
trace was available to attribute a particular reported 11-hour display to this
defect.

The repair passes the collected snapshot to `reconcileNow()`. That method enters
the existing coordinator/service path, which applies the active pair and
confirmed sharing scope, sanitizes fields, compares meaningful content, issues a
monotonic version when needed, and writes through the existing Firestore
gateway. The coordinator also retains the fresh snapshot for a later resume or
retry. A matching unit test covers the immediate publish and remembered latest
snapshot.

## Reconstructed data paths

### Local state and publish

Android system APIs and callbacks are registered in
`android/app/src/main/kotlin/com/aj/kam/MainActivity.kt`. Flutter method/event
channel adapters feed the battery, network, activity, and location collectors.
Collectors validate/normalize values and their observation times; the
`PlatformDeviceStateProvider` assembles a `DeviceStateSnapshot`;
`LocalDeviceStateRepository.refresh()` performs a fresh read and its monitoring
stream updates its in-memory cache. The root `DeviceMonitoringLifecycle` starts
and stops that stream. `deviceStateSyncCoordinatorProvider` observes snapshots
and routes them through `DeviceStateSyncCoordinator` and
`DeviceStateSyncService`.

With an active resolved pair and confirmed sharing, the service sanitizes,
performs per-document change detection, versions meaningful changes, and calls
`FirestoreDeviceStateSyncGateway`. Unchanged content is skipped; transient
failures receive bounded retries. Unauthorized/rejected writes are blocked
rather than retried indefinitely. The gateway uses server `updatedAt` and keeps
the device observation `observedAt` separate.

### Partner realtime

Authenticated pair resolution and partner sharing feed
`partnerDeviceStateProvider`. The provider watches only shared state/location
documents. `FirestorePartnerDeviceStateRepository` merges their snapshots,
parses them, and forwards stream errors. The gateway requests Firestore metadata
changes so cache-served snapshots can later become server-confirmed without a
document data change. `authorizedPartnerDeviceStateProvider` applies the latest
sharing decision before the dashboard renders the state. Provider scope changes
cancel/recreate listeners; manual refresh invalidates the partner streams rather
than adding a second listener.

### Cache and freshness

Local state has an in-memory repository cache, but explicit refresh reads the
platform again. Partner Firestore snapshots carry `isFromCache`; freshness is
derived from observation time and stale data is labelled. The dashboard's
“Updated” label uses the partner state's observation lifecycle, not a UI-open or
listener-receipt time. Firestore `updatedAt` is server synchronization metadata;
it does not replace device `observedAt`. There is no periodic state polling;
the dashboard's one-minute timer only redraws elapsed-age labels.

## Android permission findings

Location is the only device-state capability here requiring runtime location
permission. Native `locationPermissionState()` checks fine **or** coarse grant
before interpreting denial history, so an already-granted approximate grant is
not reported as missing location permission. `precise` is separately derived
from fine-location grant. Location status is read on collector refresh/start;
the app lifecycle stops observation on pause and starts/refreshes it on resume,
including return from Android Settings. Thus no source-level defect was found
that hardcodes a granted or denied state. This mapping has not been exercised on
a physical device in this validation run.

The UI already offered the runtime request when permission was requestable. For
a permanent denial it previously explained that Settings was needed but had no
action. The location card now says which Android permission is needed and offers
“Open app settings”; the existing Android MethodChannel opens this app's details
settings page. Grant recovery still flows through the normal resume refresh.
Background location remains intentionally unsupported and is not requested.

Network state, battery/charging, and display state use Android APIs that do not
require runtime permissions. Notification permission has a separate request
flow in the profile and was outside the device-state refresh root cause.

## Authorization, environment, and limits

No Firestore Rules change was needed or made. Existing rules remain the server
authorization boundary for pair membership, sharing, owner binding, field shape,
and timestamp validation. Source inspection found the app's generated Firebase
configuration identifies `gendersocialapp`, while Rules emulator tests use
`demo-kam`; actual deployed project/rules/data were not accessible, so
environment mismatch cannot be confirmed or excluded for a production report.

Screen, network, battery, and location updates are event-driven when the app is
alive, with controlled reads on resume/refresh. Android can suspend or kill the
process; no app can publish a transition it never observes. A device without
network cannot publish immediately. These limitations remain represented as
last-known/stale data; no heartbeat or backend service was added.

## Validation evidence

- Source tracing confirms the discarded-refresh-snapshot defect and the fix.
- Automated unit and UI test runs did not complete in this environment; Flutter
  commands produced no output for 30 seconds and were stopped. `flutter pub get`
  also produced no output for 90 seconds before being stopped.
- Firestore emulator validation could not start because the `firebase` command is
  not installed/available on PATH.
- No two-device or permission-settings hardware test was available.
- See `Docs/PHASE_REALTIME_PERMISSIONS_FIX_REPORT.md` for command outcomes.

This fix is not declared production-verified until automated checks and the
two-device and permission-recovery scenarios complete on suitable tooling and
devices.
