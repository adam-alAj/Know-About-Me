# Android Compatibility and Limitations

Phase 21 platform contract for the device state collectors. Android is the only supported target. The iOS directory and generated Firebase options are retained project scaffolding; iOS runtime collection is not implemented or validated.

## Build and API scope

| Setting | Value |
| --- | --- |
| Flutter SDK observed locally | 3.44.8 |
| Dart constraint | `^3.12.2` |
| Android min / compile / target SDK | 24 / 36 / 36 |
| Android Gradle Plugin / Gradle / Kotlin | 9.0.1 / 9.1.0 / 2.3.20 |
| Java and Kotlin bytecode target | 17 |
| NDK | 28.2.13676358 |

These values describe repository configuration at Phase 21. Actual build compatibility remains unverified until the Flutter/Gradle build completes in a configured environment.

## Device capability matrix

| Capability | Android implementation | Permission / behavior | Limitations |
| --- | --- | --- | --- |
| Battery and charging | Android battery broadcast via native bridge; periodic Workmanager sample | No runtime permission | Root event subscription works while process/activity remains resident; Workmanager samples at 15-minute minimum cadence but can be delayed. Charging duration is not inferred by periodic sampling and can lose continuity across observation gaps. |
| Network transport and reachability | ConnectivityManager callbacks/capabilities; periodic Workmanager sample | `ACCESS_NETWORK_STATE` | Describes OS-reported transport and validated Internet reachability, not Firebase/backend availability. Background callback/task timing is best effort. |
| Display and activity | DisplayManager state; native event bridge; periodic PowerManager sample | No runtime permission | Screen state can be sampled periodically; human activity history is not inferred. Lifecycle and OEM behavior can interrupt event observations. |
| Foreground location | LocationManager | Coarse/fine location runtime permission | Foreground only; no background permission or service. Updates are best effort and can be delayed or unavailable. |
| Notifications | Android notification manager and local notification bridge | Android 13+ `POST_NOTIFICATIONS`; app notification setting checked on all supported APIs | Permission grant does not guarantee delivery; channel and system settings still apply. |

Android 13 and newer require runtime notification permission. Location is requested only while the app is in use; permanent denial should direct the user to app settings. A one-time location grant that expires is treated as no longer granted. KAM does not declare background location or implement its own foreground service. The Workmanager dependency contributes an optional internal `SystemForegroundService`, `FOREGROUND_SERVICE_SHORT_SERVICE`, and wake-lock declarations to the merged manifest; this periodic task does not start that service.

## Offline, privacy, and lifecycle

Network connectivity, validated Internet access, Firebase availability, cached data, and stale data are separate states. A network callback cannot prove a Firebase request will succeed. See [offline, stale data, and recovery](../reliability/OFFLINE_STALE_DATA_AND_RECOVERY.md).

Battery, network, and display event subscriptions remain attached to the root monitoring owner after the app is paused, so changes may be collected and published while Android keeps the process alive. A Workmanager task samples those three supported categories and publishes through the authenticated Firestore client after checking active pairing, both consents, and the owner's current sharing settings. It also refreshes authorized partner documents into local cache. Its 15-minute minimum periodic schedule is inexact and may be delayed by Doze, standby, or OEM policy. Android can kill the process or suspend work; force-stop prevents scheduled work until the user launches KAM again. Location remains foreground-only and is never read by the background worker.

Location and device state follow the sharing/authorization boundaries in [security and authorization](../security/SECURITY_AND_AUTHORIZATION.md) and [privacy and sharing](../privacy/PRIVACY_SHARING_AND_CONNECTION_LIFECYCLE.md). Android cloud backup and device transfer are disabled/excluded for app data because local preferences may contain sensitive state. Backup rules are in `android/app/src/main/res/xml/`.

## Manual compatibility matrix

Run on an Android API 24 device/emulator and an API 33+ device/emulator. Record device model, API, grant/deny choice, and observed result for each row.

| Scenario | Expected result |
| --- | --- |
| Install, launch, deny location | App remains usable; location unavailable; no crash. |
| Grant coarse location only | Location is approximate where platform policy provides it; app remains usable. |
| Grant precise location, then revoke in Settings | Collector returns unavailable/denied and recovers after permission is granted again. |
| Grant one-time location and let it expire | Permission is requested again when location is needed; stale in-memory grant is not retained. |
| Deny location permanently | UI explains how to enable it in Settings; no repeated request loop. |
| API 32 notifications | Check app-level notification setting without runtime permission dialog. |
| API 33+ notifications | Request permission; test grant, deny, and later Settings change. |
| Wi-Fi/mobile/offline transitions | Transport and Internet validation update independently of backend state. |
| Lock/unlock and screen off/on | Display state updates when callbacks are available; unknown remains unknown. |
| Charging transition and process restart | Charging status updates; duration continuity is not assumed across restart. |
| Background app while process remains resident | Battery/network/display changes may be collected event-driven; verify Firestore writes and record any OS delay. |
| Process killed or device in Doze | Workmanager may perform a deferred current-state sample; do not expect immediate collection. Verify actual task run and publication. |
| App force-stopped in Settings | Workmanager is not expected to run until the user launches KAM again. |
| Reinstall/restore or device transfer | Sensitive local app data is not restored by configured backup rules. |

## Platform references

- [Android notification runtime permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [Android location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions/background)
- [Android background work restrictions](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions)
- [Android 12 backup behavior](https://developer.android.com/about/versions/12/behavior-changes-12)
- [Android Auto Backup](https://developer.android.com/identity/data/autobackup)
- [PowerManager.isInteractive](https://developer.android.com/reference/android/os/PowerManager#isInteractive()) and [Display.getState](https://developer.android.com/reference/android/view/Display#getState())
