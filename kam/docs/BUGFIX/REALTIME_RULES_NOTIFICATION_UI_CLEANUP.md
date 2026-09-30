# Realtime, rules/notification and UI cleanup

Focused cleanup after the device-state/location fixes: simplify what the app
*shows* and *logs*, and put the rule → notification trigger where it belongs,
without changing the architecture, Firestore or the Security Rules.

Measured results are in
[`../PHASE_REALTIME_CLEANUP_REPORT.md`](../PHASE_REALTIME_CLEANUP_REPORT.md).

---

## 1. Discovered root causes

### 1.1 Screen state reached the partner only by luck

**Symptom (reported on real devices):** turn device A's screen off, refresh
device B, and the “Screen” row in *Activity indicators* still says **On**.

**Root cause.** Three layers, in order of how directly each one produces the
symptom:

1. **The native read never returned `off` on a modern phone.** The documented
   source for `screenState` (Phase 9 `ACTIVITY_AVAILABILITY.md`) is
   `PowerManager.isInteractive()` plus the screen broadcasts. The Android
   implementation instead read only `DisplayManager`/`Display.getState()` and
   mapped `STATE_ON → on`, `STATE_OFF → off`, everything else → no value. When
   the power button is pressed, a device with an always-on display moves the
   default display to `STATE_DOZE` (and related suspend states), not
   `STATE_OFF` — so the read produced **no value**, the `on` observation was
   never replaced, and the partner kept seeing the last written `On`. This is
   the direct cause of “always On”, and the Dart-only changes below cannot fix
   it on their own.
2. The synchronization service coalesces writes behind a short **timer**. When
   the screen turns off, the app is being backgrounded, and a Dart timer does not
   run once the Android process is suspended. A screen-off observation that *was*
   made locally could still be dropped before it was written.
3. Screen off/on is a **discrete, meaningful transition**, but it was on the same
   coalescing path as a continuously changing battery percentage. There was no
   prompt path for it.

**Fix (three parts).**

* **Native read (`MainActivity.readActivityState`) now uses the documented
  source.** It first asks `PowerManager.isInteractive()`: a non-interactive
  device has its display off or dozing, and that is reported as the technical
  fact `off` rather than a missing value. Only when the device *is* interactive
  does it consult the display state to decide `on`/`off`, and it still reports
  no value (never a guess) for an interactive-but-unsettled display. This is a
  correction of an implementation/contract mismatch, not a semantic change:
  `on`/`off` remain technical facts about the display and are never a claim
  about the person.
* `DeviceMonitoringLifecycle` now has an `onBackground` hook. On the settled
  background state (`paused`) it collects the current state (which re-reads the
  display state) and publishes it **immediately**, before releasing the
  observers. `inactive` and `hidden` no longer release monitoring, because they
  are the states Android emits around the screen turning off.
* `DeviceStateSyncCoordinator` publishes **screen and charging transitions
  immediately**, bypassing the coalescing window. Battery level and other
  continuously varying values stay on the coalesced path, so a burst of readings
  still produces at most one write.

The existing change tracker still records the signature after either path, so a
later trigger cannot produce a duplicate write.

### 1.2 Notifications were only delivered while one screen was open

**Root cause.** The rule → notification decision ran inside the dashboard's
`RuleInterpretationsSection` widget. An alert therefore only reached the user
while that exact screen was mounted; on any other tab nothing was delivered. The
dedupe/cooldown bookkeeping was also process-global module state.

**Fix.** Delivery moved to a root listener,
`notificationDeliveryProvider`, mounted once in `KamApp` next to
`historyEventListenersProvider`. The section now only *displays*
interpretations. The bookkeeping lives in the provider instance and is reset when
the signed-in identity changes, so one account's cooldown/dedupe state cannot
carry into another's session. All eligibility rules (preference, staleness,
cooldown, duplicate key, permission, delivery result) are unchanged.

### 1.3 Noise in the UI and the logs

**Root causes.**

* The dashboard carried a Phase 11 *development* card (`PartnerSyncCard`) that
  printed internal synchronization details and duplicated the Privacy screen's
  sharing switches.
* The local activity/location cards were titled “(technical observations)” and
  showed lifecycle phases, freshness classifications and capability lines.
* Several messages were long, implementation-level explanations.
* `PlatformDeviceStateProvider` logged “collection started/completed” and one
  info line per non-available capability on every collection.

### 1.4 A partner value that stopped advancing still read as live

**Symptom (reported on real devices):** device A is Wi-Fi-only; Wi-Fi is switched
off, and device B's *Network* card still says **Connectivity: Online**.

**Root cause.** Two facts together:

1. A device that has lost connectivity cannot publish anything, so B keeps the
   partner's last published `networkState` (`online`). This is inherent: there is
   no push (Spark) and no polling, so an offline device cannot announce its own
   offline state.
2. The viewer did not say the value was no longer current. The partner
   `networkStatus` observation is timestamped with the partner's own
   `lastOnlineAt`, but the row only appended an age marker once the value passed
   the *stale* boundary (15 min); between 2 and 15 minutes it still read as a
   live `Online`.

**Fix.** The partner metric rows now mark a value that is no longer current the
moment it leaves the *fresh* window (2 min): `recent` → ` · last known`,
`stale` → ` · stale`. This is never turned into an “offline” claim — an absent
update is not proof that the partner's device is off or offline (the Phase 20 §8
invariant is preserved). The header already reports the partner's last observed
time; the per-value marker makes an aging value unmistakable.

---

## 2. Changes

### UI (presentation only; no state semantics changed)

* `PartnerSyncCard` removed from the dashboard and deleted. Sharing is managed in
  one place (Privacy); internal sync bookkeeping is no longer user-facing.
* `ActivitySummaryCard` simplified to **Screen**, **Activity** and **Last observed
  activity**; technical lines removed. `LocationSummaryCard` retitled
  “Location” and its labels converted from SHOUTING debug case to sentence
  case.
* Short messages in place of long ones: “Offline”, “Retrying”, “Permission
  required”, “Not shared”, “Unsupported”, “Location off”, “Stale”, “Showing
  cached data.”, “Nothing is shared yet”.
* Partner values that are no longer fresh are marked ` · last known` (or
  ` · stale`), so a partner value that stopped advancing cannot read as live.
* Connection labels remain constants, so their meaning is unchanged — only the
  copy is shorter.

### Logging

* Removed the routine “device state collection started/completed” lines and the
  per-capability info line. Failure warnings (capability failure, auth failure,
  Firestore permission failure, history/notification failures) are kept.
* No new logging was added. Nothing sensitive is logged (the existing
  key-redaction in `DeveloperAppLogger` is unchanged).

### Realtime / notification

* Root `notificationDeliveryProvider`; `RuleInterpretationsSection` is display
  only.
* Native screen state read via the documented `PowerManager.isInteractive()`
  source, so a screen turning off (including into doze) is reported as `off`.
* Immediate publish for screen/charging transitions and at background.
* All three evidence listeners already request metadata changes
  (`includeMetadataChanges: true`), so the cache → server transition of every
  document used as evidence is observed.

---

## 3. Security Rules verification

No rule was changed. The full rules suite was executed against the Firestore
emulator (see the report for the count). It covers allowed owner/partner reads,
active-pair shared-category access, and the denied cases: unauthenticated,
cross-pair, after disconnect/revoke, sharing disabled, forged ownership,
forged membership, and unauthorized notification/event creation.

## 4. Realtime / listener lifecycle

* Real-time partner updates remain listener-driven; refresh is a recovery
  mechanism only.
* One partner-state listener per (pair, partner, sharing) combination: the
  provider scope cancels the previous stream before the new one is created.
  Invalidating `partnerDeviceStateProvider` replaces it, it does not add to it.
* A manual refresh on the dashboard re-collects local state, re-derives the
  connection, re-asserts the publish, then invalidates the partner providers.

## 5. Known limitations (unchanged, accurate)

* **A device can only report while its process is alive.** If device A's screen
  turns off and its process is later suspended or killed, later transitions are
  not reported until it runs again. The fix maximises the chance that the
  screen-off transition is written at the moment it happens; it cannot make a
  suspended app observe anything.
* Notifications are local. There is no remote push on the Spark plan, so an alert
  is raised when the app is running and observing authorized state.
* Tapping a notification opens the app; authorization is re-checked by
  construction because the dashboard only reads authorized partner state.
