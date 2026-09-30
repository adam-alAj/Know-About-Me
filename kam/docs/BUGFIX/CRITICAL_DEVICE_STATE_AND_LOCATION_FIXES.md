# Critical device-state and location fixes

Scope: reliability of real-time synchronization, connectivity state, charging
duration, screen state, location and home/away, without changing the
architecture, Firestore, the Security Rules or the Android-only, Spark-only
constraints.

This document describes what was wrong, what was changed, and the semantics the
fixes preserve. The measured results are in
[`CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES_REPORT.md`](./CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES_REPORT.md).

---

## 0. The invariant that ties four of the six problems together

Four of the six reported symptoms ("no real-time refresh", "always Offline",
"charging duration never available", "screen always On") had a shared theme:
**the application was looking at a correct value and then acting on an
out-of-date copy of it, or discarding a true observation at a lifecycle
boundary.** None of them required a new backend, a new listener or a timer.

The most important single defect was metadata propagation, described next.

---

## 1. Real-time state does not refresh / manual refresh does nothing

### Root cause

Firestore `snapshots()` only re-emits when the **document data** changes; a
metadata-only change (`isFromCache` flipping from `true` to `false`, or
`hasPendingWrites` clearing) is not delivered unless
`includeMetadataChanges: true` is requested.

On a normal start, Firestore serves the local cache first (`isFromCache = true`)
and then contacts the server. When the server copy is **identical** to the
cached copy — the overwhelmingly common case for a sharing document the user
just wrote and has not touched again — no second snapshot is emitted. Every
consumer therefore read `isFromCache = true` for the whole session.

That value feeds two decisions:

* `ConnectionEvidence.hasServerConfirmedDocument` (problem 2), and
* `PairSharingState.isConfirmed` in
  `FirestoreSharingRepository` (problem 1): a cache-only sharing snapshot with
  no pending write is treated as **unknown**, so
  `DeviceStateSyncCoordinator.applyConfirmedSharing` deliberately ignores it.

The consequence is that the coordinator never applied the owner's confirmed
sharing switches, so it never published anything: `Device B` kept showing the
last document from before, `Last updated …` never advanced, and a manual UI
refresh could not help because the pipeline believed the authorization was
still unknown.

### Fix

Request metadata changes on every listener whose metadata is consumed as
evidence:

* `FirestoreDeviceStateSyncGateway.watch` — `snapshots(includeMetadataChanges: true)`
* `PairingRepository.watchPairs` — `snapshots(includeMetadataChanges: true)`
* `FirestoreSharingRepository.watch` — `snapshots(includeMetadataChanges: true)`

This does not create a listener, does not poll, and does not weaken
authorization: the rules still authorize every read and write. It only makes the
cache → server transition observable.

### Manual refresh

The dashboard refresh (`RefreshIndicator`) now re-reads real sources instead of
only rebuilding widgets:

1. `DeviceMonitoringController.collectNow()` re-collects this device's own
   capabilities from the platform collectors.
2. `ConnectionStatusController.refresh()` re-derives the connection from the
   latest evidence already held.
3. `DeviceStateSyncCoordinator.reassertLatest()` gives an unfinished publish a
   coalesced new trigger.
4. The authorized partner providers are invalidated, which cancels the old
   Firestore listener and creates exactly one new one — no duplicate listener,
   no polling loop.

---

## 2. False “Offline — showing last known data”

### Root cause

Same metadata defect as §1. `ConnectionEvidence.connectivity` reports `offline`
for documents held only from cache, and that classification is correct while the
backend really is unreachable. Because the cache → server transition was never
observed, the state stayed “cache only” forever and the banner
(`ConnectionIndicator.offlineLabel`) was shown on fully-online devices.

### Fix

With `includeMetadataChanges: true`, the server-confirmed snapshot now arrives,
`hasServerConfirmedDocument` becomes `true` and the connection resolves to
`online`; the banner hides itself.

### Semantics that are preserved (not collapsed)

`ConnectivityState`, `SynchronizationState` and `RecoveryState` remain distinct,
and partner freshness still comes from the partner's own `observedAt`. A stale
partner state while the local device is online is shown as an age
(“Last observed …”), never as “Offline”. “No news” remains `unknown`, never
`offline`.

---

## 3. Charging duration is always Unavailable / Not shared

### Root cause

`BatteryChargingCollector` tracked a charging session with an in-memory
`Stopwatch` and a `_chargingStartedAt`, and **destroyed both in `stop()`**.

Monitoring is released whenever the app leaves the foreground
(`DeviceMonitoringLifecycle`), and `stop()` is also reached through the
`watchBatteryState` cancellation path. Every backgrounding therefore discarded a
session the device had genuinely observed, so by the time the user looked at the
UI the duration was `unknown` — which the partner UI renders as “Unavailable or
not shared”.

A second issue was conceptual: the duration was an elapsed stopwatch rather than
a value derived from a timestamp, so it could not survive a process restart even
in principle.

### Fix

* The duration is now derived from timestamps:
  `chargingDuration = now − chargingStartedAt` (FR-010).
* `stop()` no longer clears the session. It only releases the native
  subscription and forgets *transition adjacency*. A session already in
  progress keeps its original start time across a monitoring gap and is cleared
  only by a real observation: a non-charging reading, an `unknown` state, or a
  read error.
* A first reading of `charging`/`full` with no observed start still yields
  `unknown` — nothing is fabricated.
* A `full` reading preserves a session whose start predates a gap.

### Semantics preserved

`Available`, `Unknown`, `Unavailable`, `Unsupported`, `Not shared` remain
distinct. Sharing is enabled ⇒ a value the device genuinely observed is
`available`; a value it could not determine is `unknown`; withdrawing the
category removes the fields.

---

## 4. Screen state is always On

### Root cause

`DeviceMonitoringLifecycle` released **all** observers on every non-resumed
lifecycle state, including the transient `inactive`. On Android the screen-off
transition arrives around `inactive`/`paused`, so the display event was dropped
when the activity collector's subscription was cancelled — the partner kept
seeing the last foreground value (`on`).

### Fix

* `inactive` no longer releases monitoring. It is a transient loss of focus (a
  dialog, the notification shade, the moments around the screen turning off),
  not backgrounding.
* On `hidden`/`paused`/`detached`, the widget performs **one bounded read** of
  the display state (`ActivityStateCollector.refresh()`) before releasing the
  observers, so a screen-off transition at the moment of backgrounding is still
  observed and published.
* A lifecycle token prevents a slow background read from tearing down a
  subscription that a following resume has already started.

This is strictly event-driven: one read per background transition. No heartbeat,
no timer, no per-second write, and the screen state is never inferred from
Flutter's app lifecycle.

---

## 5. Location cannot be determined and there is no Google Maps action

### What already worked

The Android foreground permission flow, the one-shot fix, the throttled update
stream, the permission/service/no-fix distinctions and the refusal to fabricate
a location were already implemented and remain unchanged.

### What was missing

There was **no action to open the partner's authorized location in a map** —
no map URI, no deep link, no launcher.

### Fix

* New domain boundary `MapLauncher` (`domain/sources/map_launcher.dart`).
* New Android bridge `MethodChannelMapLauncher` over the `kam/map_launcher`
  channel.
* `MainActivity` builds a standard `geo:` URI and falls back to the https
  Google Maps link if no `geo:` handler exists, returning `false` when neither
  can be started.
* The partner dashboard shows **Open in Google Maps** for a usable shared
  coordinate and **Open last known location** for a stale one, with an explicit
  caption that a stale fix is not a current position. The action is not offered
  for unavailable, unshared or malformed locations.

No new Dart package is added: the launch is a launch-only `ACTION_VIEW` intent,
consistent with the existing MethodChannel architecture. No coordinates are
logged or stored by this bridge.

### Semantics preserved

OS permission and partner sharing permission remain separate. Location states
(`Available`, `Permission required`, `Permission denied`, `Service disabled`,
`Temporarily unavailable`, `Unsupported`, `Stale`, `Not shared`, `Unknown`) are
unchanged.

---

## 6. At home / Away always Unknown, with no way to configure home

### Root cause

The home/presence derivation (`HomePresenceCalculator`, `LocationStateCollector`,
the owner-only `UserPreferences.homeLocation` and `ProfileController.setHomeLocation`)
was fully implemented, but **no screen ever called it** — there was no way for a
user to set, update or remove a home location. With no home configured, the
at-home classification correctly stayed `unknown`.

### Fix

A private **Home location** card is added to the Privacy screen, available
whether or not a partner is connected:

* shows the current status (`Not configured` / `Configured (radius … m)` /
  `Configured but switched off`);
* **Set home location** / **Update home location** captures the current device
  fix and stores it through `ProfileController.setHomeLocation`, which writes the
  owner-only `users/{uid}/settings/preferences.homeLocation`;
* **Remove home location** clears it.

The stored coordinate is never shared. Only the derived distance and
at-home/away status can travel to the partner, and only when the user shares the
`distanceFromHome` category.

### Derivation (unchanged, now reachable)

```text
current device fix + private home coordinate + configured radius
    distance <= radius  => atHome
    distance >  radius  => awayFromHome
```

If location is unavailable, permission is denied, the service is disabled, home
is not configured, or the fix is stale beyond the location policy, the result is
`unknown` — never `away`, and never `atHome`.

---

## Security, privacy and cost

* No Firestore Security Rule was changed or weakened. The emulator rules suite
  (including cross-pair isolation, category gating and offline-revocation
  scenarios) passes unchanged.
* The home coordinate stays in the owner-only preferences document; the partner
  still receives only the derived distance/presence.
* No Cloud Functions, Cloud Run, Pub/Sub or other paid backend is introduced.
* No polling loop, heartbeat or per-second write is introduced. Changes remain
  event-driven and coalesced by the existing `DeviceStateSyncService`
  change-aware pipeline.

## Android limitations (accurate, not claimed away)

* Screen transitions are only observed while the process is alive. A screen
  transition that happens after the process is killed is not reported; the next
  observation after the app returns is the current display state.
* Location is foreground-only. There is no background location, no
  `ACCESS_BACKGROUND_LOCATION` and no foreground service.
* Charging duration is `unknown` when an `charging` reading is the very first
  observation this process makes (for example charging already in progress at
  cold start) because no start time was observed. It is never fabricated.
