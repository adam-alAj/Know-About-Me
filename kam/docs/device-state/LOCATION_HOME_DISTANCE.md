> **Phase 21 platform contract:** Android is the only supported runtime target. iOS and other non-Android targets are unsupported and unvalidated; older platform-specific implementation descriptions below are historical and must not be used as the current support contract. See [Android compatibility and limitations](../platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).`r`n`r`n# Location, Home Location and Distance (Phase 10)

## 1. Purpose

Phase 10 adds a privacy-preserving, accuracy-aware location observation layer:
the device's current and last-known location, the OS permission state, the
user's explicitly configured home, the distance from home, and an
at-home/away/unknown classification. It reports only what the platform and the
user's own configuration actually support.

Three rules govern the feature:

> A stale location is not a current location.

> An unavailable location does not imply that the device is away from home.

> Distance calculations inherit uncertainty from the accuracy of the underlying
> location observation.

## 2. Architecture

```text
Location permission (explicit user action)
        ↓
Native location APIs (Android LocationManager / iOS CLLocationManager)
        ↓
LocationPlatformGateway (MethodChannelLocationGateway)
        ↓
LocationStateCollector        ← home location pushed from owner-only preferences
        ↓
DeviceLocationState + HomePresenceCalculator + GeoDistance (Haversine)
        ↓
DeviceStateSnapshot { location } → LocalDeviceStateRepository
        ↓
Future Firestore synchronization (Phase 11; not implemented)
```

Files:

- `features/location/domain/models/location_state.dart` — `Coordinate`,
  `HomeLocation` (with `enabled`), `HomePresence`, legacy `LocationState`.
- `features/location/domain/services/geo_distance.dart` — Haversine distance.
- `features/location/domain/services/home_presence_calculator.dart` — radius
  classification.
- `features/device_state/domain/models/device_location_state.dart` —
  `LocationFix`, `LocationServiceState`, `DeviceLocationState`.
- `features/device_state/domain/sources/location_platform_source.dart` —
  gateway contract and raw samples.
- `features/device_state/domain/services/location_state_collector.dart` — the
  collector.
- `features/device_state/data/location/method_channel_location_gateway.dart` +
  native `MainActivity.kt` / `AppDelegate.swift`.
- `features/device_state/data/services/shared_preferences_location_observation_store.dart`
  — single-fix persistence.
- `features/device_state/presentation/widgets/location_summary_card.dart` —
  debug visibility and the explicit permission action.
- `features/location/presentation/home_location_map_screen.dart` — the map
  picker used to identify home (see §12).

## 3. Location model

`LocationFix` carries `coordinate`, the platform's own `observedAt`, optional
`accuracyMeters`, an `approximate` flag (reduced accuracy granted by the user)
and the producing `source`. A fix is validated (`Coordinate.isValid`): NaN,
infinite or out-of-range values are rejected, never clamped.

`DeviceLocationState` carries:

| Field | Meaning |
| --- | --- |
| `location` | Newest fix with usability attached: `available` while current, `stale` once too old, or the reason it is missing |
| `lastKnownLocation` | The same fix labelled as history, with its original timestamp |
| `permission` | Normalized `DevicePermissionState` |
| `serviceState` | `enabled` / `disabled` / `unknown` for the OS location service |
| `distanceFromHome` | Derived metres, with the fix's accuracy retained |
| `presence` | `atHome` / `awayFromHome` / `stale` / `unsupported` / `unknown` |
| `homeConfigured`, `homeEnabled`, `homeRadiusMeters` | Home configuration facts only — never coordinates |

Home coordinates deliberately never enter the snapshot: only derived values
leave this layer, so the exact home position cannot leak through a later
synchronization.

## 4. Permission model

`DevicePermissionState` (Phase 6, extended in Phase 10) covers `granted`,
`denied`, `permanentlyDenied`, `restricted`, `limited`, `notDetermined`,
`unknown` and `notApplicable`.

- The OS prompt is only ever triggered by an explicit user action (the "Allow
  location access" action in the debug card). Nothing auto-prompts.
- After `permanentlyDenied` or `restricted`, `requestPermission()` does not call
  the platform at all — it re-reads the status and reports the blocking reason.
- Android cannot distinguish "never asked" from "asked and permanently denied"
  so the collector tracks whether a request has happened in this process. That
  is documented as best-effort and resets when the process restarts.
- iOS reports `notDetermined`, `denied`, `restricted`, `authorizedWhenInUse`
  and `authorizedAlways`; only when-in-use is requested.

## 5. Availability states

Location uses the shared `CapabilityAvailability` vocabulary plus one Phase 10
addition:

| State | Meaning |
| --- | --- |
| `available` | A fix exists and is current enough for the 30-minute window |
| `stale` | A fix exists but is too old to treat as current |
| `permissionDenied` | The app has no location access (`permissionState` says which kind) |
| `serviceDisabled` | Permission is fine but the OS location service is off |
| `unavailable` | Supported, temporarily not accessible |
| `unsupported` | The platform cannot provide location at all |
| `error` | A read failed (timeout, provider error, malformed fix) with a safe reason |
| `unknown` | Genuinely no information |

These never collapse into a single `null` location. In particular
`serviceDisabled` and `permissionDenied` are distinguishable, and both differ
from `stale`.

## 6. Freshness and staleness

`FreshnessPolicy.location` (fresh ≤ 5 min, recent ≤ 30 min, stale beyond) is
used for fixes. `DeviceLocationState.freshnessAt` follows the current
observation when it has a timestamp, otherwise the retained history, and is
`unknown` when neither exists.

A stale fix keeps its value and its real timestamp but is labelled `stale` in
the model, so it can never be rendered as the current position.

## 7. Accuracy semantics

`accuracyMeters` is the platform's own value and is never estimated, rounded
away or improved. `approximate` records a reduced-accuracy grant (Android 12+
approximate permission, iOS 14+ reduced accuracy): such a fix is shown as
approximate and the `preciseLocation` capability stays `permissionRequired`
until the user upgrades the grant. Distance is always presented next to the
accuracy that limits it (for example `740m (±40m)`).

## 8. Current vs last-known location

`location` answers "can this be used as the current position?" and
`lastKnownLocation` answers "what was the most recent fix we ever had?".
Restoring a stored fix does not change its `observedAt`, so after a restart an
old fix is still old. The debug card prints both lines separately.

## 9. Android support (verified)

| Capability | API | Status |
| --- | --- | --- |
| Foreground location | `LocationManager` GPS / network providers, no Play Services dependency | Verified (`flutter build apk --debug`) |
| Precise vs approximate | `ACCESS_FINE_LOCATION` vs `ACCESS_COARSE_LOCATION` grant | Verified |
| Permission state | Runtime request + `shouldShowRequestPermissionRationale` heuristic | Verified |
| Service disabled | `LocationManager.isLocationEnabled` (API 28+) or provider checks | Verified |
| Background location | Not requested, not implemented | Out of scope (never claimed) |

Android notes: a cached last-known fix is only returned as current when it is
younger than one minute; otherwise a single update is requested with a 12 s
timeout before falling back to the cached fix (with its real timestamp) or a
`timeout` reason. Requesting either fine or coarse location is a single dialog;
the user may grant approximate only, which is preserved as `approximate`.

## 10. iOS support (documented, not built here)

| Capability | API | Status |
| --- | --- | --- |
| Foreground location | `CLLocationManager.requestLocation()` / `startUpdatingLocation()` | Implemented (public APIs only); not buildable on this Windows host |
| Precise vs approximate | `accuracyAuthorization` (iOS 14+) | Implemented |
| Permission state | `authorizationStatus` + `requestWhenInUseAuthorization()` | Implemented |
| Service disabled | `CLLocationManager.locationServicesEnabled()` | Implemented |
| Background location | No background mode, no "always" authorization | Never requested |

`NSLocationWhenInUseUsageDescription` explains the purpose in user-facing
language. No private APIs, no undocumented background execution.

## 11. Foreground/background limitations

Location is collected only while the app is in the foreground and monitoring is
active. `DeviceMonitoringLifecycle` starts observation on resume and stops it on
inactive/paused/detached. No background permission, foreground service,
WorkManager or BGTaskScheduler is used, and no continuous tracking is claimed.

## 12. Home location

Home is **explicitly user-configured** in the owner-only profile
(`users/{uid}/settings/preferences`, Firestore Rules: owner-read only). It is
never inferred from GPS history, frequent locations, overnight location, Wi-Fi,
IP address or movement patterns — no automatic detection exists anywhere in the
code.

Create / update / delete go through the existing `profile_controller`
(`setHomeLocation`, `setHomeLocation(null)`); restrict/disable uses the
`HomeLocation.enabled` flag, which is persisted with the profile and defaults to
enabled for documents written before the flag existed.

### Identifying home on a map

The Privacy screen's *Home location* card offers two ways to set the point:

- **Identify home on map** opens `HomeLocationMapScreen`, an in-app map
  (`flutter_map` over OpenStreetMap tiles, `latlong2` coordinates) with a pin
  fixed at the centre of the map. The user pans until the pin is on their home
  and confirms; the point under the pin is what is stored. The map opens at the
  configured home, or otherwise at this device's fix, so it never starts at a
  wide view and jumps. If neither exists it opens wide with an explicit notice
  and the user can still pan to a home.
- **Use current location** / **Update from current location** keeps the earlier
  direct action: the stored point becomes this device's current fix.

An update preserves the existing label, radius and enabled flag; only the point
changes. The map is an action, not an observation: it records no trail, performs
no polling, and infers nothing from movement. Map tiles are the only network
request the screen makes, and the coordinate is never placed in a URL, log or
error message. Tiles are served by the public OpenStreetMap tile servers under
their [tile usage policy](https://operations.osmfoundation.org/policies/tiles);
attribution is rendered on the map, and a private two-person app is well within
light-use expectations. If the app ever needs heavier use, a self-hosted or
commercial tile endpoint should replace the public one at that single
`urlTemplate`.

## 13. Home radius

`HomeLocation.radiusKm` (default 0.3 km = 300 m) is configurable per user, and
`radiusMeters` exists so kilometres cannot be compared with metres by accident.
A disabled home keeps its coordinates but produces no distance and no presence
statement.

## 14. Distance calculation

`GeoDistance.metersBetween` implements the Haversine formula on a mean earth
radius of 6 371 008.8 m. Plain latitude/longitude subtraction is never used, and
invalid coordinates return `null` instead of a guessed distance. Verified
against known values: one degree of latitude ≈ 111.2 km, the same longitude
delta at 60° latitude is ≈ half the equatorial distance, and Jerusalem→Tel Aviv
≈ 54 km.

## 15. At-home / away semantics

Presence is produced only from a usable fix **and** an enabled, valid home:

| Situation | Presence |
| --- | --- |
| Distance ≤ radius (boundary inclusive) | `atHome` |
| Distance > radius | `awayFromHome` |
| Fix older than 30 minutes | `stale` |
| No fix / denied / service disabled / no home / home disabled / invalid home | `unknown` |
| Platform cannot provide location | `unsupported` |

`awayFromHome` is never produced from missing information. `nearHome` exists in
the enum for a future configurable near band and is not produced by this phase.
Distance and presence are recalculated from the same fix when home changes — a
configuration change is not a movement event and no observation time changes.

## 16. Privacy decisions

Collected: permission/service state, one current fix, one retained last-known
fix, and the derived distance/presence. Persisted locally: a single fix (JSON,
one key). Stored in the owner-only profile: home coordinates, radius, enabled
flag. Never collected: location history, trails, movement analytics, Wi-Fi SSIDs
or BSSIDs, IP-derived location, Bluetooth inference, nearby devices, geofences.
Coordinates are never logged, never put in error messages, never sent to
analytics — the collector logs nothing at all, and the native bridges log
nothing. The debug card prints coordinates only in debug builds.

OS permission and partner sharing are separate: granting location access never
starts sharing with the partner. `SharingCategory.location` /
`distanceFromHome` remain user-controlled, and Phase 11 must honour them.

## 17. Battery optimization

- One fix per refresh, requested only when permission and the service allow it.
- Native throttling while monitoring: minimum 60 s **and** 100 m between Android
  updates; iOS uses `distanceFilter = 100 m` with
  `kCLLocationAccuracyHundredMeters`.
- No Dart timers, no polling loop, no duplicate listeners: a single subscription
  exists only while monitoring is active, and it is cancelled on stop, on
  revoked permission, and on `dispose`.
- A recent cached fix (≤ 60 s) is reused instead of asking the GPS again.

## 18. Local persistence

One SharedPreferences key (`device_state.last_known_location`) holding a single
`LocationFix` (latitude, longitude, platform `observedAt`, accuracy,
approximate flag, source). It is overwritten by the next fix and never grows
into a history. On restart the fix is restored at its original time; a future
timestamp is discarded, a malformed record is deleted, and a storage failure
degrades to "no history" rather than failing the collector. Home persists in the
owner-only profile, independently of transient fixes.

## 19. Error handling

Permission denial, permanent denial, restriction, disabled service, unsupported
platform, timeout, provider errors, invalid coordinates, invalid accuracy,
malformed payloads and storage failures each produce a normalized state with a
safe reason string. The location collector never throws into the snapshot
assembly: a location failure leaves battery, charging, network, activity and
availability untouched (covered by tests).

## 20. Known limitations

- No background or terminated-app location; foreground only.
- Android "permanently denied" is heuristic (rationale flag + in-process
  request tracking) and can be reported as `denied` after a process restart.
- No fused/Play Services provider on Android: GPS and network providers only,
  with a 12 s one-shot timeout.
- iOS was not built on this Windows host; the Swift bridge is written against
  public APIs and shares the same Dart layer validated by tests.
- Freshness windows (5 min / 30 min) and the "recent cached fix" threshold
  (60 s) are policy choices.
- Location accuracy from the OS varies; a fix can be several hundred metres off
  when the user grants approximate location.

## 21. Phase 11 integration boundary

Phase 10 stops at the local snapshot: `DeviceLocationState` inside
`DeviceStateSnapshot`. Phase 11 may transmit derived values (availability,
timestamp, accuracy, distance, presence) with authenticated ownership, active
pair consent and `SharingCategory` respect. Home coordinates and raw coordinates
stay local unless a later phase explicitly designs and privacy-reviews their
sharing. No Firestore writes, no Cloud Functions, no paid services, no location
heartbeat exist in this phase.

## Platform capability matrix

| Capability | Android | iOS | Notes |
| --- | --- | --- | --- |
| Foreground location | Verified | Implemented, not built | Requires permission; foreground only |
| Precise location | Verified | Implemented, not built | User may grant approximate only |
| Approximate location | Verified (`approximate` flag) | Implemented (`accuracyAuthorization`) | Never upgraded silently |
| Background location | Not implemented | Not implemented | Reported `unsupported`; never claimed |
| Service-disabled detection | Verified | Implemented | Distinct from permission denial |
| Home location | App-level (owner-only profile) | App-level | Never inferred |
| Distance calculation | App-level Haversine | App-level Haversine | Shared normalized logic |

"Verified" means exercised in this repository: unit tests, `flutter analyze`,
and an Android debug APK build. iOS is implemented but cannot be compiled here.

## Manual validation matrix

| Scenario | Expected | Where verified |
| --- | --- | --- |
| A — Permission granted (device) | Fix obtained, accuracy captured, timestamp and freshness correct | `location_state_collector_test.dart`; on-device via debug card |
| B — Permission denied | `permissionDenied` with the exact permission reason; no fabricated location | Collector tests |
| C — Location services disabled | `serviceDisabled`, distinct from denial | Collector tests |
| D — Stale location | `stale` label plus real age; never shown as current | Collector + availability tests |
| E — Home configured | Distance and `atHome` correct | `home_presence_calculator_test.dart`, collector tests |
| F — Outside radius | `awayFromHome` (spec example: 640 m > 200 m radius) | Calculator tests |
| G — Unknown location | `unknown` presence, never `awayFromHome` | Collector test "an unavailable location never becomes away from home" |
| H — Restart | Original timestamps preserved; history ages to stale | Collector restart tests |
| I — Location failure | Battery/activity/network keep working | Collector error-isolation test |
| J — Approximate location | Reported as approximate with its real accuracy | Collector reduced-accuracy test |

## Related documentation

- [`DEVICE_STATE_ARCHITECTURE.md`](DEVICE_STATE_ARCHITECTURE.md)
- [`DEVICE_STATE_MODEL.md`](DEVICE_STATE_MODEL.md)
- [`PLATFORM_CAPABILITY_MATRIX.md`](PLATFORM_CAPABILITY_MATRIX.md)
- [`ACTIVITY_AVAILABILITY.md`](ACTIVITY_AVAILABILITY.md)
- [`NETWORK_MONITORING.md`](NETWORK_MONITORING.md)
