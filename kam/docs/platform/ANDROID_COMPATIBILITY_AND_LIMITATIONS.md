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
| Battery and charging | Android battery broadcast via native bridge | No runtime permission | Charging duration is process-local and only measured after an observed transition; restarts and collection gaps lose continuity. |
| Network transport and reachability | ConnectivityManager network callbacks and capabilities | `ACCESS_NETWORK_STATE` | Describes OS-reported transport and validated Internet reachability, not Firebase/backend availability. |
| Display and activity | DisplayManager default display state; native activity event bridge | No runtime permission | Unknown/intermediate display state is not treated as on or off. App lifecycle and OEM behavior can interrupt observations. |
| Foreground location | LocationManager | Coarse/fine location runtime permission | Foreground only; no background permission or service. Updates are best effort and can be delayed or unavailable. |
| Notifications | Android notification manager and local notification bridge | Android 13+ `POST_NOTIFICATIONS`; app notification setting checked on all supported APIs | Permission grant does not guarantee delivery; channel and system settings still apply. |

Android 13 and newer require runtime notification permission. Location is requested only while the app is in use; permanent denial should direct the user to app settings. A one-time location grant that expires is treated as no longer granted. The app does not declare background location access or a foreground service.

## Offline, privacy, and lifecycle

Network connectivity, validated Internet access, Firebase availability, cached data, and stale data are separate states. A network callback cannot prove a Firebase request will succeed. See [offline, stale data, and recovery](../reliability/OFFLINE_STALE_DATA_AND_RECOVERY.md).

Collectors are best effort while the app process is active. Android may suspend or terminate background processes, and callbacks can be delayed by power management, OEM policy, permission changes, or unavailable hardware. This implementation does not promise continuous background monitoring.

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
| Background app for an extended period | Treat delayed/missed samples as expected platform limitation; no continuous guarantee. |
| Reinstall/restore or device transfer | Sensitive local app data is not restored by configured backup rules. |

## Platform references

- [Android notification runtime permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [Android location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions/background)
- [Android background work restrictions](https://developer.android.com/develop/background-work/background-tasks/bg-work-restrictions)
- [Android 12 backup behavior](https://developer.android.com/about/versions/12/behavior-changes-12)
- [Android Auto Backup](https://developer.android.com/identity/data/autobackup)
- [PowerManager.isInteractive](https://developer.android.com/reference/android/os/PowerManager#isInteractive()) and [Display.getState](https://developer.android.com/reference/android/view/Display#getState())
