> **Phase 21 platform contract:** Android is the only supported runtime target. iOS and other non-Android targets are unsupported and unvalidated; older platform-specific implementation descriptions below are historical and must not be used as the current support contract. See [Android compatibility and limitations](../platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).`r`n`r`n# Battery and Charging Monitoring (Phase 7)

## Normalized state

`BatteryState` contains independent `StateObservation` values for percentage,
charging state, duration, and charging source, plus an optional
`chargingStartedAt`. Percentage accepts only integral values from 0 through
100. Null is unavailable; malformed/out-of-range values are errors. Each field
has its own observation timestamp and availability/freshness metadata.

Charging states are `charging`, `full`, `discharging`, `notCharging`, and
`unknown`. An unavailable API result is represented by observation availability
(`unavailable` or `error`) rather than pretending it is `notCharging`. Android
can report `notCharging`; iOS reports charging/full/unplugged/unknown, with
unplugged normalized to discharging. A full battery is not inferred from 100%;
it is reported only when the platform says full.

Charging source is USB/AC/wireless/unknown only when Android reports a plugged
type. iOS exposes no source in the API used here and reports it unsupported.
No battery health or temperature is collected.

## Charging session and duration

The collector creates a session start only after it has observed a known
non-charging state followed by charging. A first reading of charging or full
has unknown start and duration. Charging-to-full preserves a known session;
non-charging, unknown, unavailable, error, or stopped observation clears it.
There is no persistent charging history or Firestore telemetry.

Elapsed duration uses a process-local monotonic `Stopwatch`, so wall-clock
changes do not distort it. Monitoring stop/background suspension invalidates
the session because transitions may have been missed. App restart or reboot
therefore starts with unknown duration, even if the phone is currently
charging. The next observed non-charging-to-charging transition establishes a
new start. Durations beyond 30 days are rejected defensively.

## Collection and freshness

Android reads `ACTION_BATTERY_CHANGED` and listens only while the Flutter event
stream is subscribed. iOS enables UIKit battery monitoring while reading and
listens to battery level/state notifications; Apple posts battery level
notifications no more frequently than once per minute. No polling loop or
permission is added. `refresh()` is on demand; `watchBatteryState()` is
event-driven and releases its listener on cancellation.

Percentage and charging-state observations use the shared standard freshness
policy. Staleness is computed from `observedAt`; an unchanged value is not made
fresh. Battery collection is local and does not depend on network or pairing.

## Serialization and authorization boundary

`DeviceStateSnapshot.battery` serializes the normalized battery fields. It is
only a local observation at this stage. Phase 11 owns synchronization and must
enforce authenticated device ownership, active pair consent, and Firestore
Security Rules. No behavior interpretation is included.

## Platform references

- [Android BatteryManager](https://developer.android.com/reference/android/os/BatteryManager)
- [Apple battery level](https://developer.apple.com/documentation/uikit/uidevice/batterylevel)
- [Apple battery state](https://developer.apple.com/documentation/uikit/uidevice/batterystate-swift.enum)
- [Apple battery monitoring](https://developer.apple.com/documentation/uikit/uidevice/isbatterymonitoringenabled)
- [Apple battery level change notification](https://developer.apple.com/documentation/uikit/uidevice/batteryleveldidchangenotification)

