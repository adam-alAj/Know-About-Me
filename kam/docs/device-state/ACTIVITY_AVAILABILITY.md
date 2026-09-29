> **Phase 21 platform contract:** Android is the only supported runtime target. iOS and other non-Android targets are unsupported and unvalidated; older platform-specific implementation descriptions below are historical and must not be used as the current support contract. See [Android compatibility and limitations](../platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).`r`n`r`n# Activity and Availability Monitoring (Phase 9)

## Purpose

Phase 9 observes what the device and platform *actually expose* about display
state, supported activity signals, this application's lifecycle, and local
availability — and represents everything else honestly as `unknown` or
`unsupported`. It is a device-state observation layer, not a behavioural
inference system.

Two rules govern the whole feature:

> The system does not guarantee continuous global phone-activity monitoring.

> Lack of recent activity does not prove that the phone is powered off, the
> user is asleep, or the user is not using the device.

There is no `phonePoweredOff` state in the model, and no statement of the form
"user is sleeping / awake / using the phone / ignoring you" may be derived
here. Interpretation belongs to the later Rule Engine (Phase 13+) and must
remain explicitly user-defined.

## Architecture

```text
Native platform signals (Android screen broadcasts; Flutter app lifecycle)
        ↓
Platform gateway (ActivityPlatformGateway / MethodChannelActivityGateway)
        ↓
ActivityStateCollector            ← app lifecycle pushed by DeviceMonitoringLifecycle
        ↓
DeviceAvailabilityDeriver (evidence from every observation + lastObservedActivityAt)
        ↓
ActivityState / DeviceAvailabilityEvidence  (normalized models)
        ↓
PlatformDeviceStateProvider → DeviceStateSnapshot { activity, availability }
        ↓
LocalDeviceStateRepository → local application state
        ↓
Future Firestore synchronization (Phase 11; not implemented)
```

Files:

- `lib/features/device_state/domain/models/activity_state.dart` —
  `ActivityState`, `DeviceScreenState`, `ActivityStatus`, `AppLifecyclePhase`.
- `lib/features/device_state/domain/models/device_availability_evidence.dart`
  — evidence-based availability.
- `lib/features/device_state/domain/sources/activity_platform_source.dart` —
  platform-neutral gateway contract.
- `lib/features/device_state/domain/services/activity_state_collector.dart` —
  event-driven collection and timestamp rules.
- `lib/features/device_state/domain/services/device_availability_deriver.dart`
  — conservative availability derivation.
- `lib/features/device_state/domain/services/activity_observation_store.dart`
  + `data/services/shared_preferences_activity_observation_store.dart` —
  minimal persistence.
- `lib/features/device_state/data/activity/method_channel_activity_gateway.dart`
  — Android method/event channel bridge.
- `lib/features/device_state/presentation/widgets/activity_summary_card.dart` —
  debug visibility card on the dashboard.

## Supported metrics

| Metric | Source | Value model |
| --- | --- | --- |
| `screenState` | Android `PowerManager.isInteractive` + `ACTION_SCREEN_ON/OFF` events | `DeviceScreenState { on, off, unknown }` inside a `StateObservation` |
| `activityState` | Derived from whichever signals are available | `ActivityStatus { activityDetected, noActivityObserved, unknown }` |
| `lastActivity` | Timestamp of the most recent *observed* signal event | `ActivityState.lastObservedActivityAt` (`DateTime?`) |
| `appLifecycle` | Flutter `WidgetsBindingObserver`, pushed into the collector | `AppLifecyclePhase { foreground, background, inactive, hidden, detached, unknown }` |
| `deviceAvailability` | Derived from all observations + last observed activity | `DeviceAvailabilityEvidence` with `CapabilityAvailability` |

## Exact semantics

### Screen state

`on`/`off` are technical facts about the display. `unknown` means the platform
API reported "not determinable"; `unsupported` means the platform has no such
API; `error` means a read failed; `unavailable` means the platform returned no
value. These are never collapsed into one another, and `on` never means "the
person is looking at the phone".

### `lastObservedActivityAt`

> The most recent timestamp at which the application observed a supported
> activity signal.

It is updated **only** when a real event is observed:

- an Android screen on/off transition between two known states, or
- an observed application-lifecycle transition (the first report after start
  only establishes the phase and does **not** count).

It is never updated by a plain refresh, an application restart, a process
recreation, or restoring persisted history. It does **not** mean last touch,
last unlock, last app opened, last awake, or last interaction unless the
platform actually exposed that specific event — and no such platform event is
used here.

### Activity status

`activityDetected` means *at least one observed signal is active* (screen `on`
or app in `foreground`). `noActivityObserved` means every available signal is
inactive. It is a signal statement, never a behavioural one. When no signal
can say anything, the status is `unknown` — never `noActivityObserved`.

### Activity duration (`activityStartedAt` / `activityDuration`)

A start is established only by an observed transition into the detected state
within the current monitoring session. If the app starts while a signal is
already active, duration is `unknown` — it is never computed as
`now - appStart`. Elapsed time uses a process-local monotonic `Stopwatch`, so
wall-clock changes cannot distort it. Monitoring stop, native stream `onDone`,
and read errors invalidate the session because transitions may have been
missed; the historical `lastObservedActivityAt` survives.

### App lifecycle

Describes **this application only**. `appLifecycle = background` with
`screenState = on` (or `unknown`) is valid and means nothing about the person:
they may be using another application. Lifecycle reports continue while
monitoring is stopped; a lifecycle push requires no native subscription.

### Device availability

Evidence-based: `available` when a valid local signal (any `available`
observation or `lastObservedActivityAt`) is within the freshness window;
`stale` when evidence exists but is too old, keeping
`lastConfirmedAvailableAt`; `unknown` when nothing was ever observed;
`unsupported` / `permissionDenied` / `error` / `unavailable` mirror the
underlying observations (checked in that order when no positive evidence
exists). Availability is **reachability evidence**, never proof of power
state, network state, or Firebase synchronization.

## Screen-state limitations

- Only Android exposes display state to third-party apps
  (`PowerManager.isInteractive`, no permission).
- iOS exposes no public screen on/off API; the capability is `unsupported`
  and no approximation (brightness notifications, protected-data state, Screen
  Time API, private APIs) is used.
- Screen events reach only dynamically registered receivers while the process
  is alive; they cannot wake a terminated app.
- A first reading of an already-`on` screen is recorded with its own
  `observedAt`, but creates no activity timestamp and no duration start.

## Activity limitations

- Global user activity (what any app is doing, touch events, unlocks) is not
  observable and is not modelled.
- No Accessibility Service, notification listener, usage-stats access or
  installed-app inventory is used.
- `lastObservedActivityAt = null` ("never observed") is a normal state.
- After restart, restored history keeps its historical time and ages to
  `stale`; it is never re-stamped.

## Availability semantics and freshness/staleness

Observations use the shared `FreshnessPolicy.standard` (fresh ≤ 2 min,
recent ≤ 15 min, stale beyond); the app-lifecycle observation uses
`FreshnessPolicy.slow` (fresh ≤ 15 min, stale beyond 2 h) because it changes
infrequently. `ActivityState.freshnessAt` follows the display observation when
supported, otherwise the lifecycle observation.

`DeviceAvailabilityEvidence.freshnessAt` classifies the age of
`lastConfirmedAvailableAt` — the evidence, not the assessment time. `stale`
and `unknown` are distinct: stale means "we saw something, but it is old";
unknown means "we have never seen anything".

## Android capabilities (verified)

| Capability | API | Status |
| --- | --- | --- |
| Display interactive state | `PowerManager.isInteractive()` — no permission | Verified (official docs) |
| Display on/off events | `Intent.ACTION_SCREEN_ON` / `ACTION_SCREEN_OFF` to dynamically registered receivers | Verified; cannot wake a terminated process |
| App lifecycle | Flutter `WidgetsBindingObserver` | Verified |
| Device availability | Derived locally | Derived |

Android restrictions discovered during implementation: screen broadcasts are
`FLAG_RECEIVER_REGISTERED_ONLY`-style system broadcasts — a killed process
receives nothing until the user reopens the app, so background observation is
best-effort while the process lives. Nothing polls while the app is
backgrounded: `DeviceMonitoringLifecycle` stops monitoring when Flutter
reports inactive/paused/detached.

## iOS capabilities (handled conservatively)

| Capability | Status |
| --- | --- |
| Display state | **Unsupported** — no public API; represented as `unsupported`, never approximated |
| Global user activity | **Unsupported** — restricted by the platform; not modelled |
| App lifecycle | Supported (Flutter framework) |
| Activity signals / availability | Supported via app lifecycle only; screen-derived parts remain `unsupported`/`unknown` |

No private APIs, undocumented internals or Screen Time/MDM entitlements are
used. iOS was not built in this environment (Windows host); the shared Dart
implementation is validated by unit tests and `flutter analyze`.

## Permissions

None. No permission is requested for activity monitoring: Android
`isInteractive` and screen-broadcast reception require no grant, and the app
lifecycle is framework-level. No invasive permission (usage access,
accessibility, notification listener) was added. `permissionDenied` remains a
representable state for future metrics but is never triggered today.

## Privacy decisions

Data minimization: only display state, this app's lifecycle, and a single
last-observed-activity timestamp are collected. Never collected: keystrokes,
screenshots, microphone, camera, message/notification content, contacts, call
content, browser history, installed apps, or per-app usage. No Accessibility
Service. The persisted timestamp is a single value, not a timeline. The debug
card labels everything as a technical observation; partner-facing exposure is
explicitly out of scope until Phase 12/13 authorization exists.

## Battery-efficiency strategy

Event-driven only: native screen events and pushed lifecycle reports update
state; `refresh()` is on demand (initial collection and explicit reads). No
polling loop, no timer, no background scheduler, no wake lock, no Firestore
heartbeat. The receiver is registered only while the event stream is
subscribed and is released on cancel/destroy.

## Persistence

One SharedPreferences key: `device_state.last_observed_activity_at` (UTC
ISO-8601). Written only when an observed signal event updates
`lastObservedActivityAt`. On restart the value is restored at its historical
time (future timestamps are ignored; storage failures degrade to "no
history"). Screen state and in-progress durations are deliberately *not*
persisted: screen state is re-readable on Android, and re-anchoring a
historical duration would fabricate continuity. No activity history or
surveillance timeline exists.

## Error isolation

Each collector fails independently. A failed screen read becomes an `error`
observation on `screenState` alone; lifecycle, battery, network and snapshot
assembly continue (covered by tests). Errors carry a diagnostic string, logs
record capability names and error types only — never values, user IDs or
tokens. Persistence failure never invalidates a successful observation.

## Known limitations

- No monitoring while the process is dead; no WorkManager/BGTaskScheduler
  (deferred with the background-monitoring phase).
- `lastObservedActivityAt` can be `null` forever on a device where no signal
  event is ever observed (e.g. iOS user who never backgrounds the app).
- On iOS the activity picture is app-lifecycle-only; screen state stays
  `unsupported`.
- Availability windows (2 min / 15 min) are policy choices, not physics.
- iOS build not validated on this Windows host.

## Debug visibility

The dashboard's "Activity and availability (technical observations)" card
renders screen state, activity status, last observed activity, app lifecycle,
observed-at, freshness, capability support and device availability as raw
combined-text lines, making `Unsupported` / `Unknown` / `Stale` explicit. It
is a development aid, not a partner-facing interpretation UI.

## Manual validation matrix

| Scenario | Expected | Where verified |
| --- | --- | --- |
| A — Screen/activity supported (Android device) | Card shows `Screen state: ON/OFF`, freshness `Fresh`, timestamps advance only on events | On-device (debug APK) |
| B — Unsupported capability (iOS or desktop) | `Screen state: Unsupported`, capability line "unsupported on this platform", no fabricated values | Unit tests + widget tests |
| C — App background | `App lifecycle: BACKGROUND` while screen stays `ON`/`Unknown`; activity does not become "none" because of the background alone | `activity_state_collector_test.dart` ("background lifecycle never rewrites the screen observation") |
| D — No recent observation | `Stale (last confirmed …)` distinguishable from `UNKNOWN` | `device_availability_test.dart` ("stale is distinguishable from unknown") |
| E — Provider failure | Screen read error does not break battery/network; availability still derived from other evidence | `activity_state_collector_test.dart` ("activity failure does not break battery collection") |
| F — Application restart | Restored timestamp keeps historical time; old history is `stale`, never `available`; no fabricated observation | `device_availability_test.dart` restart tests |

## Platform references

- [Android PowerManager.isInteractive](https://developer.android.com/reference/android/os/PowerManager#isInteractive())
- [Android broadcast overview (registered receivers)](https://developer.android.com/develop/background-work/background-tasks/broadcasts)
- [Android Intent.ACTION_SCREEN_ON](https://developer.android.com/reference/android/content/Intent#ACTION_SCREEN_ON())
- [Apple UIApplication lifecycle](https://developer.apple.com/documentation/uikit/uiapplication)
- [Apple Screen Time API (not used; entitlement-gated)](https://developer.apple.com/documentation/deviceactivity)

## Future Phase 11 integration boundary

Phase 9 stops at the local `DeviceStateSnapshot { activity, availability }`.
Phase 11 may transmit these fields as part of meaningful state-change
snapshots under authenticated device ownership, active pair consent and
Firestore Security Rules. Phase 11 must not turn them into a high-frequency
heartbeat, and must keep carrying `observedAt`, freshness and
`unsupported`/`unknown` distinctions to the partner. No Cloud Functions, no
paid Firebase services, no server-side polling are required or added.

## Related documentation

- [`DEVICE_STATE_ARCHITECTURE.md`](DEVICE_STATE_ARCHITECTURE.md)
- [`PLATFORM_CAPABILITY_MATRIX.md`](PLATFORM_CAPABILITY_MATRIX.md)
- [`BATTERY_CHARGING.md`](BATTERY_CHARGING.md)
- [`NETWORK_MONITORING.md`](NETWORK_MONITORING.md)
