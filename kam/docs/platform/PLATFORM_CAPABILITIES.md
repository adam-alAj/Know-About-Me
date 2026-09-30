# Platform Capabilities — Current Android Contract

**Supported runtime:** Android only. Other Flutter targets and iOS-specific
folders/options are scaffolding; they are not supported or validated product
targets. This matrix is based on the current Android manifest, Kotlin
`MainActivity`, Dart adapters/collectors, and
[`ANDROID_COMPATIBILITY_AND_LIMITATIONS.md`](ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).
Runtime device validation is still BLOCKED; see the Phase 26 and 27 reports.

## Capability matrix

| Capability | Current Android implementation | Permission | Semantics and limits |
| --- | --- | --- | --- |
| Battery level | Android battery APIs and native bridge | None | Snapshot/event-driven, normalized 0–100 when available; unknown/error remain explicit. |
| Charging | Android battery broadcast/native bridge | None | Charging, not charging, full, or unknown. Charging duration is based on observed transitions and is not preserved across process restart. |
| Network | `ConnectivityManager` callback and `NetworkCapabilities` | `ACCESS_NETWORK_STATE` | Transport and OS-validated Internet path are observations; neither proves Firebase availability. No network does not mean phone off. |
| Display/activity | Display state plus app/native observation bridge | None | Screen/display state and app activity are limited observations. Screen off is not sleep; no evidence is not inactivity. OEM/lifecycle gaps are possible. |
| Device availability | Derived from successful sync/last-seen observations | None | Active/recent/offline/unknown indicate reachability evidence only, not physical power state. |
| Foreground location | Native `LocationManager` bridge | Coarse and/or fine location, requested contextually | Foreground only. Approximate accuracy, service state, denial, and stale time must be represented. No background collection. |
| Notifications | Local native notification channel (`Rule alerts`) through MethodChannel | `POST_NOTIFICATIONS` on Android 13+; app settings also apply | Local delivery is best effort. Generic title/body; no partner details in lock-screen text. No FCM or remote push. Delivery requires actual device validation. |
| App lifecycle | Flutter lifecycle owner and Android Activity lifecycle | None | Monitoring stops/refreshes around lifecycle changes. Android may suspend or kill background work; no 24/7 guarantee. |

## Permission and sharing are separate

OS permission only permits local collection. The signed-in user must separately
enable the category for the partner, and Firestore Rules enforce that sharing
decision on remote access. A locally available value is not automatically
authorized for sharing.

The manifest declares Internet, network state, foreground coarse/fine location,
and notification permission. It does not declare background location or a
foreground service. Android 13+ notification permission can be denied; earlier
versions still depend on app/channel settings.

## Required state semantics

```text
UNKNOWN != FALSE
UNSUPPORTED != FALSE
STALE != CURRENT
ERROR != FALSE
PERMISSION DENIED != UNSUPPORTED
NO NETWORK != PHONE OFF
NO FIRESTORE UPDATE != PHONE OFF
BACKGROUND SUSPENSION != PHONE OFF
SCREEN OFF != USER SLEEPING
NO ACTIVITY EVIDENCE != USER INACTIVE
OS PERMISSION != PARTNER SHARING PERMISSION
CACHE != CURRENT AUTHORIZATION
```

Use a timestamped statement such as “Location updated 2 hours ago”; do not
present stale data as current or say “currently at home.” Show “unavailable” or
“last seen” rather than “powered off” without a trustworthy power-state signal;
this app has no such signal.

## Android limitations

- Background execution varies by Android version, power state, app standby, and
  manufacturer policy. Collection/listeners can be delayed or stopped.
- Battery duration loses continuity across observation gaps/restarts.
- Network transport/validated reachability does not prove access to Firebase.
- Location is foreground-only, permission-dependent, and may be approximate or
  stale; there is no continuous or background location service.
- Android may terminate the app. Resume triggers re-observation; it cannot
  recover events the OS never delivered.
- Notification permission, channel settings, battery policy, and device settings
  can prevent an alert even when a rule matched.
- Physical device/API-level permission, lifecycle, and release behavior have not
  been validated in this environment.
