# Platform Capability Matrix

Phase 6 contains no native collectors. Therefore the runtime adapter currently
reports all detailed metrics unsupported; this is deliberate and does not claim
that the OS cannot expose them. The matrix describes the researched project
boundary and the implementation status separately.

| Capability | Android | iOS | Permission | Background support | Phase 6 status / limitation |
|---|---|---|---|---|---|
| Battery | API exists | API exists | None typically | OS-controlled | Collector deferred to Phase 7; no runtime value claimed |
| Charging | API exists | API exists | None typically | OS-controlled | Collector deferred to Phase 7; duration needs observed transitions |
| Network | Connectivity APIs exist | Network path API exists | Android network-state permission | May become stale | Collector deferred to Phase 8; transport is not proof of backend reachability |
| Screen state | Limited receiver/usage APIs | No general screen-state API | Android special usage access for some signals | Restricted | Deferred; do not claim parity or continuous state |
| Activity | Own app lifecycle | Own app lifecycle | None for own-app lifecycle | Restricted | Device activity classification deferred to Phase 9 |
| Location | Foreground/background APIs | When-in-use/always APIs | Location permission | Limited/opportunistic | Deferred to Phase 10; no permission added/requested |
| Background monitoring | WorkManager is deferred and opportunistic | BGTaskScheduler is deferred and opportunistic | No general permission | Restricted by OS | No scheduler or 24/7 promise |

The project has Android and iOS runner folders; Android min SDK follows
`flutter.minSdkVersion`, and the iOS deployment target is 13.0. There is no
location permission in either manifest/plist. Android has no monitoring
permission added. iOS builds require macOS/Xcode and cannot be validated on this
Windows host.

Source reference for the detailed OS restrictions: the project-maintained
[`PLATFORM_CAPABILITIES.md`](../platform/PLATFORM_CAPABILITIES.md), which links
Android and Apple primary documentation. Recheck these limits when a later
phase selects native APIs or dependencies.
