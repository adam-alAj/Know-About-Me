# Platform Capability Matrix

What Android and iOS **actually permit** for each capability the SRS mentions.
Phase 1 produces no monitoring code; this matrix is the contract later phases
must respect. Flutter does not remove platform restrictions (SRS constraint 7).

Legend for **Reliable?**:

- **Yes** — observable whenever the app has the permission and is running.
- **Partial** — observable, but the OS may delay, batch or suspend collection;
  the app must therefore report age/staleness rather than assume currency.
- **No** — the platform does not expose it; the metric must be modelled as
  *unsupported* (FR-068).

## 1. Summary table

| Capability | Android | iOS | Reliable? | Required Permission? | Notes |
| --- | --- | --- | --- | --- | --- |
| Battery percentage | `BatteryManager.BATTERY_PROPERTY_CAPACITY`, `ACTION_BATTERY_CHANGED` (sticky) | `UIDevice.batteryMonitoringEnabled` + `batteryLevel` | Yes | No | `batteryLevel` is `-1` when monitoring is disabled → treat as unknown. |
| Charging state | `BatteryManager.isCharging`, `EXTRA_STATUS` | `UIDevice.batteryState` | Yes | No | Distinguish charging / not charging / full. |
| Charging duration | Derived from observed start/stop transitions | Derived from observed start/stop transitions | Partial | No | Correct only while transitions are observed. Never assume charging continued while state was unknown (FR-010). |
| Battery state changes | `ACTION_BATTERY_CHANGED` / `ACTION_POWER_CONNECTED/DISCONNECTED` | KVO on `batteryLevel`/`batteryState` | Partial | No | Background delivery depends on the app being alive or scheduled. |
| Network connectivity | `ConnectivityManager` + `NetworkCallback` | `NWPathMonitor` | Yes | Android: `ACCESS_NETWORK_STATE` | Reports transport (Wi-Fi/mobile) and reachability, not internet quality. |
| Online / offline (app to backend) | App-derived from successful sync | App-derived from successful sync | Yes | No | This is the *app's* reachability, not proof about the person (FR-070). |
| Last online timestamp | Last successful backend sync | Last successful backend sync | Yes | No | An observation, not a guarantee of current reachability. |
| Offline duration | Derived | Derived | Partial | No | Derived from last-seen; becomes stale while the app is suspended. |
| Screen / activity state | `ACTION_SCREEN_ON/OFF` only while a receiver is registered; `UsageStatsManager` approximations | **Not available** | No | Android: `PACKAGE_USAGE_STATS` (special) | iOS exposes no screen on/off API. Model as *unsupported* on iOS. |
| App activity (own app) | `ProcessLifecycleOwner` | `UIApplication` lifecycle | Yes | No | Only the app's own foreground/background state; says nothing about the phone's screen. |
| Last activity timestamp | Derived from own app lifecycle / device events | Derived from own app lifecycle | Partial | No | Must be described as "last *observable* activity" (FR-017). |
| Foreground location | `FusedLocationProviderClient` | `CLLocationManager` (when-in-use) | Yes | Android: `ACCESS_FINE`/`ACCESS_COARSE_LOCATION`; iOS: `NSLocationWhenInUseUsageDescription` | Accuracy is reported and must be surfaced (FR-020). |
| Background location | `ACCESS_BACKGROUND_LOCATION` + location foreground service (Android 10+) | "Always" authorization, background `location` mode, significant-change / region monitoring | Partial | Android: `ACCESS_BACKGROUND_LOCATION`; iOS: `NSLocationAlwaysAndWhenInUseUsageDescription` | OS may delay or suspend; significant-change updates are coarse. Never imply continuous tracking. |
| Home / away classification | Derived from last known location + configured radius | Derived from last known location + configured radius | Partial | Same as location | Classification is only as current as the location it is derived from. |
| Distance from home | Derived (haversine) | Derived (haversine) | Partial | Same as location | Must be labelled approximate when the location is approximate or stale (FR-023). |
| Device reachability / availability | Derived from last successful sync | Derived from last successful sync | Yes | No | Classify as active / recently seen / offline / unknown (FR-015). |
| Device power-off detection | **Not available** | **Not available** | No | — | Apps cannot reliably observe shutdown (Android `ACTION_SHUTDOWN` is not guaranteed to complete work; iOS has no API). **Never** claim powered off (FR-015, FR-070). |
| Background execution | `WorkManager` (periodic, min ~15 min), foreground services | `BGTaskScheduler` (`BGAppRefreshTask`, `BGProcessingTask`) | Partial | No | Timing is opportunistic, not guaranteed; Doze/App Standby and Low Power Mode defer work. |
| Background synchronization | WorkManager + Firestore offline queue | BGTaskScheduler + Firestore offline queue | Partial | No | Must recover and sync on resume (FR-060, NFR-044). |
| Push notifications | Firebase Cloud Messaging | APNs via FCM | Partial | Android 13+: `POST_NOTIFICATIONS`; iOS: user authorization | Delivery is best-effort; a rule event must still appear in history if a push fails (FR-044). |
| App lifecycle | Reliable | Reliable | Yes | No | Used to resync and to timestamp "last seen". |

## 2. Capabilities that must be modelled as reduced or unsupported

These are the "do not hide problems" cases (SRS constraints 3 and 10). Each is
representable in the domain model rather than faked:

| Capability | Phase 1 representation |
| --- | --- |
| Screen state on iOS | `DataAvailability.unsupported` |
| Device powered off | *Does not exist as a state.* Only reachability + last-seen time. |
| Continuous background monitoring | Value retained with its timestamp; freshness becomes `recent`/`stale`. |
| Continuous location tracking | Last-known location + `accuracyMeters` + freshness. |
| Charging duration across unknown states | Duration resets/pauses rather than assuming continuation. |

## 3. Consequences for the product

1. **Age is part of the value.** Because most background capabilities are only
   *partial*, every metric carries `observedAt` and is classified as
   fresh/recent/stale (FR-047, FR-061, NFR-025).
2. **Platform differences are visible.** The UI must communicate "unsupported on
   this platform" rather than showing a blank or a guess (NFR-019).
3. **Battery efficiency is a design constraint.** Prefer event-driven collection
   and scheduled work over continuous polling (NFR-009, NFR-010, FR-071).
4. **Notifications are best-effort.** Rule events live in history independently
   of push delivery (FR-044).

## 4. Official references

Android:

- Background work: <https://developer.android.com/develop/background-work/background-tasks>
- WorkManager: <https://developer.android.com/topic/libraries/architecture/workmanager>
- BatteryManager: <https://developer.android.com/reference/android/os/BatteryManager>
- ConnectivityManager: <https://developer.android.com/reference/android/net/ConnectivityManager>
- Location permissions: <https://developer.android.com/develop/sensors-and-location/location/permissions>
- Battery optimization / Doze: <https://developer.android.com/training/monitoring-device-state/doze-standby>

Apple:

- Background Tasks: <https://developer.apple.com/documentation/backgroundtasks>
- `UIDevice.batteryState`: <https://developer.apple.com/documentation/uikit/uidevice/batterystate>
- Core Location and background updates: <https://developer.apple.com/documentation/corelocation>
- Requesting location authorization: <https://developer.apple.com/documentation/corelocation/requesting_authorization_to_use_location_services>
- Background execution limits: <https://developer.apple.com/documentation/uikit/about_the_app_launch_sequence>

Firebase (see also `ADR-002-firebase-boundaries.md`):

- Cloud Messaging delivery: <https://firebase.google.com/docs/cloud-messaging>

> Verified against the platform documentation above. Android behaviour reflects
> API level 34+ (Android 14); iOS behaviour reflects iOS 17+. Both evolve, so a
> capability listed as *Partial* or *No* must be re-checked before implementing
> the corresponding collector in a later phase.
