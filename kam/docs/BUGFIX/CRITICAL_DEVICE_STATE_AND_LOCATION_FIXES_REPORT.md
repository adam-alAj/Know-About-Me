# Critical device-state and location fixes — report

Companion to
[`CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES.md`](./CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES.md).

Everything below was run in this workspace. Nothing that was not run is
reported as passing.

---

## 1. Root causes

### Problem 1 — real-time state does not refresh

```text
Problem:     Device B shows the partner's old value and manual refresh does not update it.
Root cause:  Firestore snapshots() excludes metadata-only changes, so a sharing
             document whose cached copy equals the server copy never re-emitted
             with isFromCache=false. PairSharingState.isConfirmed therefore stayed
             false, DeviceStateSyncCoordinator.applyConfirmedSharing ignored the
             snapshot, and the coordinator published nothing. The manual refresh
             only invalidated the partner providers, so it could not repair the
             withheld publish.
Affected:    FirestoreDeviceStateSyncGateway, FirestoreSharingRepository,
             PairingRepository, DeviceStateSyncCoordinator path,
             PartnerReassuranceDashboard refresh.
Fix:         includeMetadataChanges: true on the three evidence listeners; make the
             refresh re-collect local state, re-derive the connection and re-assert
             the publish before invalidating partner providers.
```

### Problem 2 — false “Offline — showing last known data”

```text
Problem:     Both devices are online but the banner says Offline.
Root cause:  The same missing metadata propagation. ConnectionEvidence classifies
             cache-only documents as offline, which is correct only while the
             backend is genuinely unreachable; because the cache→server transition
             was never observed, "cache only" persisted and the device reported
             itself offline forever.
Affected:    Same listeners as problem 1.
Fix:         includeMetadataChanges: true, so the server-confirmed snapshot arrives
             and connection resolves to online.
```

### Problem 3 — charging duration always Unavailable / Not shared

```text
Problem:     Charging duration is never shown even with charging sharing enabled.
Root cause:  BatteryChargingCollector stored the session start in memory and
             cleared it in stop(). Monitoring is released whenever the app leaves
             the foreground, so each backgrounding discarded the observed session;
             the duration also used an elapsed Stopwatch instead of a timestamp.
Affected:    BatteryChargingCollector, DeviceMonitoringLifecycle path.
Fix:         derive duration from chargingStartedAt and the current clock; keep the
             session across stop(); clear it only on a real non-charging/unknown/
             error observation.
```

### Problem 4 — screen state always On

```text
Problem:     The partner never sees Screen Off.
Root cause:  DeviceMonitoringLifecycle released all observers on `inactive`, the
             state Android emits around the screen turning off. The display event
             reached a collector whose subscription had already been cancelled.
Affected:    DeviceMonitoringLifecycle, ActivityStateCollector.
Fix:         don't release monitoring on `inactive`; read the display state once at
             the background transition before releasing the observers, guarded by a
             lifecycle token so a resume cannot be torn down by a slow read.
```

### Problem 5 — location unusable and no Google Maps action

```text
Problem:     No action opens the partner's location in a map.
Root cause:  No map launcher existed: no Android intent bridge, no Dart boundary,
             no UI action.
Affected:    MainActivity (Android), new MapLauncher/ MethodChannelMapLauncher,
             new PartnerLocationActions widget, dashboard location card.
Fix:         add a launch-only geo:/https map bridge and an "Open in Google Maps" /
             "Open last known location" action for authorized coordinates only.
```

### Problem 6 — At home / Away always Unknown, no home configuration

```text
Problem:     Users cannot configure a home location.
Root cause:  The home model, calculator and ProfileController.setHomeLocation were
             implemented but no screen called them.
Affected:    PrivacyScreen (new private Home location card).
Fix:         add set/update/remove home location from the current device fix,
             stored owner-only; derivation itself is unchanged.
```

---

## 2. Files changed

Application code:

```text
android/app/src/main/kotlin/com/aj/kam/MainActivity.kt
    + kam/map_launcher MethodChannel: builds a geo: intent with an https
      Google Maps fallback; validates the coordinate; never logs it.

lib/features/device_state/data/sync/firestore_device_state_sync_gateway.dart
    includeMetadataChanges: true for the partner document listeners.

lib/features/device_state/data/repositories/firestore_sharing_repository.dart
    includeMetadataChanges: true for the sharing listener (fixes isConfirmed).

lib/features/pairing/data/pairing_repository.dart
    includeMetadataChanges: true for the membership listener.

lib/features/device_state/domain/services/battery_charging_collector.dart
    timestamp-derived charging duration; preserve the session across stop().

lib/features/device_state/presentation/providers/device_monitoring_lifecycle.dart
    don't stop on `inactive`; capture the display state at background (token-guarded).

lib/features/device_state/presentation/providers/device_state_providers.dart
    + mapLauncherProvider.

lib/features/device_state/domain/sources/map_launcher.dart            (new)
lib/features/device_state/data/maps/method_channel_map_launcher.dart  (new)
lib/features/device_state/presentation/widgets/partner_location_actions.dart (new)
    the map action boundary, Android bridge and dashboard button.

lib/features/dashboard/presentation/partner_reassurance_dashboard.dart
    real manual refresh; location card footer with the map action.

lib/features/privacy/presentation/privacy_screen.dart
    private Home location set/update/remove card.
```

Tests:

```text
test/unit/battery_charging_collector_test.dart      (updated + new duration test)
test/widget/device_monitoring_lifecycle_test.dart    (new inactive test)
test/widget/privacy_screen_accessibility_test.dart   (new home-configuration test)
test/unit/map_launcher_test.dart                     (new)
test/widget/partner_location_actions_test.dart       (new)
```

`test/unit/battery_charging_collector_test.dart` previously asserted that
`stop()` **invalidates** a charging session. That assertion encoded the defect
and was updated to assert the corrected behaviour (the session survives a
monitoring gap). No security test was removed or weakened, and the Firestore
rules test suite is byte-for-byte unchanged.

Documentation:

```text
docs/BUGFIX/CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES.md
docs/BUGFIX/CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES_REPORT.md
```

---

## 3. Test results (actual, this run)

```text
flutter analyze:       0 issues
flutter test:          693 / 693 passed
Firestore emulator:    125 / 125 passed
flutter build apk --debug: PASS (build/app/outputs/flutter-apk/app-debug.apk)
two-device manual test: NOT RUN (see §4)
```

The historical baseline was 617 Flutter tests / 114 emulator tests; the counts
above are the counts from this run, which additionally include the new tests for
these fixes. `flutter pub get` completed successfully.

Test commands:

```bash
flutter pub get
flutter analyze
flutter test
firebase emulators:exec --only firestore "npm --prefix firebase test"
flutter build apk --debug
```

---

## 4. Manual two-device test results

```text
Test              Device A            Device B            Expected                         Result
----------------- ------------------- ------------------- -------------------------------- --------
Real-time         change state        observe update      new state without restart        NOT RUN
Connectivity      online              online              no “Offline” banner               NOT RUN
Charging          start charging      see Charging+dur    charging and valid duration      NOT RUN
Screen            lock then unlock    see Off then On     screen transitions reported       NOT RUN
Location          grant + fix         see authorized loc. + Google Maps action              NOT RUN
Home              set home, move      At Home then Away   correct classification            NOT RUN
```

Two physical Android devices were **not available in this workspace**, so the
mandatory two-device validation was not performed. No device behaviour is
claimed from automated tests alone.

---

## 5. Remaining limitations

Only limitations that actually remain:

1. **Two-device validation was not run.** The code-level and automated evidence
   is complete, but the two-device acceptance test in the specification could
   not be executed here.
2. **Screen transitions require a live process.** If the app process is killed
   while the screen is off, that transition is not reported; the next state is
   the display state observed when the app runs again. This is an Android
   platform limitation, not a defect introduced here.
3. **Charging duration at cold start.** If charging is already in progress the
   first time this process observes power state, no start time was observed, so
   the duration is `unknown`. It is never fabricated. Across a normal background
   and resume the session is preserved.
4. **Foreground-only location.** No background location, no
   `ACCESS_BACKGROUND_LOCATION`, no foreground service; location updates stop
   when the app is not running.
5. **Home radius is fixed at the existing default (300 m).** The UI sets,
   updates and removes the home location; adjusting the radius is not exposed.

---

## 6. Final status

```text
INCOMPLETE
```

All six defects have an identified root cause, a smallest-correct-layer fix and
automated coverage; analysis, unit/widget tests, the Firestore emulator rules
suite and the debug APK build all pass. The mandatory two-device manual
validation still has to be performed on real hardware before the task can be
called COMPLETE.
