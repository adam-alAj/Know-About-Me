# Platform Capability Matrix

Phase 6 supplied the adapter boundary; Phase 7 adds native battery/charging
collection. Other runtime capabilities remain unsupported until their phase
adds a collector. The matrix distinguishes OS support from the implementation
currently present in this project.

| Capability | Android | iOS | Permission | Background support | Phase 7 status / limitation |
|---|---|---|---|---|---|
| Battery | `ACTION_BATTERY_CHANGED` level/scale | `UIDevice.batteryLevel` while monitoring is enabled | None | Android receiver while process runs; iOS notifications while app is active | Implemented in Phase 7; invalid/null levels remain errors/unavailable |
| Charging | Battery intent status and plugged source | `UIDevice.batteryState` (charging/full/unplugged/unknown) | None | Event driven while app runs; app restart loses unobserved transitions | Implemented in Phase 7; iOS charger source unsupported |
| Network | Connectivity APIs exist | Network path API exists | Android network-state permission | May become stale | Collector deferred to Phase 8; transport is not proof of backend reachability |
| Screen state | Limited receiver/usage APIs | No general screen-state API | Android special usage access for some signals | Restricted | Deferred; do not claim parity or continuous state |
| Activity | Own app lifecycle | Own app lifecycle | None for own-app lifecycle | Restricted | Device activity classification deferred to Phase 9 |
| Location | Foreground/background APIs | When-in-use/always APIs | Location permission | Limited/opportunistic | Deferred to Phase 10; no permission added/requested |
| Background monitoring | WorkManager is deferred and opportunistic | BGTaskScheduler is deferred and opportunistic | No general permission | Restricted by OS | No scheduler or 24/7 promise |

The Phase 7 native bridge reads system battery broadcasts on Android and UIKit
battery notifications on iOS. Android exposes `EXTRA_PLUGGED` for USB/AC/
wireless categories; the iOS API does not expose charger type. UIKit battery
level/state require battery monitoring enabled. References: [Android
BatteryManager](https://developer.android.com/reference/android/os/BatteryManager),
[Apple battery level](https://developer.apple.com/documentation/uikit/uidevice/batterylevel),
[Apple battery state](https://developer.apple.com/documentation/uikit/uidevice/batterystate-swift.enum),
and [Apple battery monitoring](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled).

The project has Android and iOS runner folders; Android min SDK follows
`flutter.minSdkVersion`, and the iOS deployment target is 13.0. There is no
location permission in either manifest/plist. Android has no monitoring
permission added. iOS builds require macOS/Xcode and cannot be validated on this
Windows host.

Source reference for the detailed OS restrictions: the project-maintained
[`PLATFORM_CAPABILITIES.md`](../platform/PLATFORM_CAPABILITIES.md), which links
Android and Apple primary documentation. Recheck these limits when a later
phase selects native APIs or dependencies.
