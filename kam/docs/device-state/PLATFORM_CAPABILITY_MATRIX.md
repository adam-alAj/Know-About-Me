# Platform Capability Matrix

Phase 6 supplied the adapter boundary; Phases 7 and 8 add native battery,
charging, and network collection; Phase 9 adds display-state, activity-signal
and evidence-based availability observation. Other runtime capabilities remain
unsupported until their phase adds a collector. The matrix distinguishes OS
support from the implementation currently present in this project. Detailed
Phase 9 semantics live in
[`ACTIVITY_AVAILABILITY.md`](ACTIVITY_AVAILABILITY.md).

| Capability | Android | iOS | Permission | Background support | Implementation status / limitation |
|---|---|---|---|---|---|
| Battery | `ACTION_BATTERY_CHANGED` level/scale | `UIDevice.batteryLevel` while monitoring is enabled | None | Android receiver while process runs; iOS notifications while app is active | Implemented in Phase 7; invalid/null levels remain errors/unavailable |
| Charging | Battery intent status and plugged source | `UIDevice.batteryState` (charging/full/unplugged/unknown) | None | Event driven while app runs; app restart loses unobserved transitions | Implemented in Phase 7; iOS charger source unsupported |
| Network transport | `ConnectivityManager` default network callback | `NWPathMonitor` | Android `ACCESS_NETWORK_STATE`; none on iOS | Event-driven only while app/process monitoring is active | Implemented in Phase 8; no Wi-Fi identifiers or addresses collected |
| Internet reachability | System `NET_CAPABILITY_VALIDATED` evidence | Not directly validated by `NWPathMonitor` | Same as transport | May become stale | Android validated/unvalidated; iOS remains unknown for a satisfied path |
| Online / offline | Validated default route is online | Satisfied path is online | Same as transport | App can be suspended or terminated | Does not mean Firebase reachable, person active, or device powered on |
| Offline duration | Observed online-to-offline transition | Observed satisfied-to-unsatisfied transition | None | Resets across lifecycle gaps | Unknown unless start observed in active monitoring session |
| Screen state | `PowerManager.isInteractive` (no permission) + `ACTION_SCREEN_ON/OFF` to registered receivers | **No public API** — must stay `unsupported` | None | Android: only while the process is alive; cannot wake a terminated app | Implemented in Phase 9 (Android only); iOS never approximated |
| Activity signals | Screen transitions + own app lifecycle | Own app lifecycle only | None | Restricted — process must be alive; monitoring stops when backgrounded | Implemented in Phase 9; signal status only, no behaviour interpretation |
| Last observed activity | Observed screen/lifecycle transitions | Observed lifecycle transitions | None | Restored history keeps its time and ages to stale | Phase 9; never fabricated by refresh, restart or restore |
| App lifecycle | Flutter `WidgetsBindingObserver` | Flutter `WidgetsBindingObserver` | None | App-level only; not device usage | Implemented in Phase 9; kept separate from screen state |
| Device availability | Derived from local evidence (observations + last observed activity) | Derived from local evidence | None | Local only; no heartbeat | Phase 9; `available`/`stale`/`unknown`/`unsupported`/`error`, never power state |
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

Phase 8 network details and platform references are in
[`NETWORK_MONITORING.md`](NETWORK_MONITORING.md). In particular, iOS satisfied
path is not proof of Internet access, and Android validation is not proof that
Firebase or any particular backend is reachable.

The project has Android and iOS runner folders; Android min SDK follows
`flutter.minSdkVersion`, and the iOS deployment target is 13.0. There is no
location permission in either manifest/plist. Android has no monitoring
permission added. iOS builds require macOS/Xcode and cannot be validated on this
Windows host.

Source reference for the detailed OS restrictions: the project-maintained
[`PLATFORM_CAPABILITIES.md`](../platform/PLATFORM_CAPABILITIES.md), which links
Android and Apple primary documentation. Recheck these limits when a later
phase selects native APIs or dependencies.
