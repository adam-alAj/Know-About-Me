# Realtime, rules/notification and UI cleanup — report

Companion to
[`BUGFIX/REALTIME_RULES_NOTIFICATION_UI_CLEANUP.md`](./BUGFIX/REALTIME_RULES_NOTIFICATION_UI_CLEANUP.md).

Everything below was run in this workspace. Nothing that was not run is reported
as passing.

---

## 1. Scope

A focused cleanup on top of the earlier
[`critical device-state and location fixes`](./BUGFIX/CRITICAL_DEVICE_STATE_AND_LOCATION_FIXES_REPORT.md):

1. Simplify what the app *shows* and *logs*.
2. Put the rule → notification trigger where it belongs (root, not one screen).
3. Verify the Firestore Rules, the rule → notification chain and the realtime
   two-device flow, without changing the architecture, the Firestore data model
   or the Security Rules.

No redesign, no paid backend, no polling.

---

## 2. Root causes fixed

### 2.1 Screen state stuck on “On” (reported on real devices)

```text
Problem:     Turn device A's screen off, refresh device B, and the “Screen” row
             in Activity indicators still says On.
Root cause:  Three layers.
             (1) The native read deviated from its documented source. Phase 9
                 ACTIVITY_AVAILABILITY.md names PowerManager.isInteractive() plus
                 the screen broadcasts, but MainActivity.readActivityState() read
                 only Display.getState() and mapped STATE_ON -> on,
                 STATE_OFF -> off, everything else -> no value. On a device with
                 an always-on display, pressing power moves the display to
                 STATE_DOZE, not STATE_OFF, so the read produced no value and the
                 old "on" observation was never replaced.
             (2) Coalescing: the sync service batches writes behind a timer, and a
                 timer does not run once the process is suspended.
             (3) Screen off/on is a discrete transition but shared the coalesced
                 path with continuously changing values.
Affected:    MainActivity.kt, DeviceMonitoringLifecycle, DeviceStateSyncCoordinator.
Fix:         native read uses PowerManager.isInteractive() (non-interactive ->
             "off") as documented; DeviceMonitoringLifecycle publishes the current
             state at background before releasing observers; the coordinator
             publishes screen/charging transitions immediately.
```

### 2.2 Notifications only delivered while one screen was open

```text
Problem:     A matched rule reached the user only while the dashboard was mounted.
Root cause:  Delivery ran inside RuleInterpretationsSection using process-global
             module state for dedupe/cooldown.
Affected:    rule_interpretations_section.dart.
Fix:         root notificationDeliveryProvider (notification_delivery_providers.dart),
             mounted in KamApp; bookkeeping reset on identity change; the section
             is display-only.
```

### 2.3 A partner value that stopped advancing still read as live

```text
Problem:     Device A is Wi-Fi-only; Wi-Fi is off, but device B's Network card
             still says “Connectivity: Online”.
Root cause:  (1) A device with no connectivity cannot publish, so B keeps the
                 partner's last published networkState; this is inherent on the
                 Spark plan (no push, no polling).
             (2) The viewer did not mark the value as no longer current until it
                 passed the stale boundary (15 min); between 2 and 15 minutes it
                 read as a live “Online”.
Affected:    partner_reassurance_dashboard.dart (_metric).
Fix:         partner metric rows mark a value that is no longer fresh the moment
             it leaves the fresh window (2 min): recent -> “ · last known”,
             stale -> “ · stale”. Never an “offline” claim: an absent update is
             not proof the partner's device is off or offline.
```

### 2.4 UI and log noise

```text
Problem:     A Phase 11 development card, "(technical observations)" titles and
             per-collection info logs.
Root cause:  Development scaffolding left in a user-facing screen and in routine
             logging.
Fix:         PartnerSyncCard removed and deleted; activity/location cards
             simplified and shortened; connection labels shortened; routine
             collection logs removed (failures still logged).
```

---

## 3. What was verified

* **Firestore Rules** — no rule changed. The full rules suite runs against the
  emulator and covers owner/partner reads, active-pair shared-category access, and
  the denied cases (unauthenticated, cross-pair, after disconnect/revoke, sharing
  disabled, forged ownership/membership, unauthorized notification/event creates).
* **Rule → notification chain** — preference → indeterminate → notMatched →
  cooldown → duplicate → notify, all still enforced; the trigger now runs at the
  application root regardless of which screen is open.
* **Realtime listener lifecycle** — one partner-state listener per
  (pair, partner, sharing) combination; a manual refresh re-collects local state,
  re-derives the connection, re-asserts the publish and then replaces the partner
  providers (it does not add a listener). All three evidence listeners use
  `includeMetadataChanges: true`.

---

## 4. Files changed

Application code:

```text
android/app/src/main/kotlin/com/aj/kam/MainActivity.kt
    readActivityState() now uses PowerManager.isInteractive() (documented source)
    and only consults Display.getState() when the device is interactive.

lib/features/device_state/data/sync/device_state_sync_coordinator.dart
    immediate publish for screen/charging transitions (_isSignificantTransition).

lib/features/device_state/presentation/providers/device_monitoring_lifecycle.dart
    onBackground hook (publish before release); inactive/hidden no longer release.

lib/app/app.dart
    root listeners; onResume/onBackground wiring.

lib/features/notifications/presentation/providers/notification_delivery_providers.dart (new)
    root notification delivery + dedupe/cooldown, reset on identity change.

lib/features/rules/presentation/widgets/rule_interpretations_section.dart
    display-only.

lib/features/device_state/data/providers/platform_device_state_provider.dart
    routine collection logs removed.

lib/core/ui/widgets/connection_indicator.dart
    shortened labels.

lib/features/dashboard/presentation/partner_reassurance_dashboard.dart
    simplified messages; map-action footer; PartnerSyncCard usage removed;
    freshness marker on partner metric values (_metric / _freshnessNote).

lib/features/device_state/presentation/widgets/activity_summary_card.dart
lib/features/device_state/presentation/widgets/location_summary_card.dart
    simplified; partner_sync_card.dart deleted.
```

Tests:

```text
test/unit/device_state_sync_coordinator_test.dart     (immediate-transition test)
test/widget/device_monitoring_lifecycle_test.dart      (inactive / background tests)
test/widget/notification_staleness_test.dart
test/widget_test.dart                                  (updated headings)
test/widget/partner_reassurance_dashboard_test.dart    (updated copy + last-known test)
```

Documentation:

```text
docs/BUGFIX/REALTIME_RULES_NOTIFICATION_UI_CLEANUP.md
docs/PHASE_REALTIME_CLEANUP_REPORT.md
```

No security test was removed or weakened. The Firestore rules test suite is
unchanged.

---

## 5. Test results (actual, this run)

```text
flutter analyze:            0 issues
flutter test:               696 / 696 passed
Firestore emulator rules:   125 / 125 passed
flutter build apk --debug:  PASS (build/app/outputs/flutter-apk/app-debug.apk)
two-device manual test:     NOT RUN (see §6)
```

The historical baseline was 617 Flutter tests / 114 emulator tests; the counts
above additionally include the tests added for these fixes. `flutter pub get`
completed successfully and the debug APK build compiles the changed Kotlin.

Test commands:

```bash
flutter pub get
flutter analyze
flutter test
firebase emulators:exec --only firestore "npm --prefix firebase test"
flutter build apk --debug
```

---

## 6. Manual two-device test results

```text
Test                    Device A              Device B            Expected                                   Result
----------------------- --------------------- ------------------- ------------------------------------------ --------
Screen on/off           turn screen off       observe Screen      Screen shows Off (then On on unlock)       NOT RUN
Real-time state         change shared state   observe update      new state without restart                  NOT RUN
Network staleness       turn Wi-Fi off        observe Network     Online marked last known, then stale        NOT RUN
Notifications           trigger a rule        receive local alert alert raised while app runs            NOT RUN
Refresh recovery        (offline window)      pull to refresh     fresh server state, no duplicate listener  NOT RUN
Charging duration       start charging        see Charging+dur    charging and valid duration                NOT RUN
Location / home         grant + fix, set home see location, home   authorized location + map action           NOT RUN
```

Two physical Android devices were **not available in this workspace**, so the
mandatory two-device validation was not performed. No device behaviour is claimed
from automated tests alone, and the screen-state fix in particular has not been
confirmed on hardware.

---

## 7. Remaining limitations

1. **Two-device validation was not run.** The code-level and automated evidence
   is complete, but the live two-device test could not be executed here. In
   particular the reported “screen always On” symptom must be re-checked on two
   real devices.
2. **A device can only report while its process is alive.** If the app process is
   suspended or killed after the screen turns off, later transitions are not
   reported until the app runs again. The fix maximises the chance that the
   screen-off transition is written at the moment it happens; it cannot make a
   suspended app observe anything.
3. **Notifications are local.** There is no remote push on the Spark plan, so an
   alert is raised when the app is running and observing authorized state.
4. **A partner with no connectivity cannot report itself.** With no push on the
   Spark plan and no polling, an offline device cannot announce that it went
   offline. The viewer therefore shows the last known value marked ` · last
   known` / ` · stale` rather than a false “Offline”. It is deliberate that an
   absent update is never turned into an offline or power-off claim.
5. **Alternative platforms.** iOS remains unsupported/unvalidated; Android is the
   only supported target.

---

## 8. Final status

```text
INCOMPLETE
```

All three areas have an identified root cause, a smallest-correct-layer fix and
automated coverage; analysis, unit/widget tests, the Firestore emulator rules
suite and the debug APK build all pass. The mandatory two-device manual
validation — including re-confirming the screen off/on transition — still has to
be performed on real hardware before this can be called COMPLETE.
