# Phase 6 — Device State Monitoring Foundation

**Status:** Implementation present; validation incomplete because Flutter/Dart
commands did not finish on the available host.

## Implementation summary

- Added normalized partial `DeviceStateSnapshot`, per-capability observations,
  explicit availability/support/permission states, timestamps, freshness, and
  JSON serialization.
- Added platform adapter and `DeviceStateProvider` contracts. The Phase 6
  adapter reports detailed collectors unsupported; battery, charging, network,
  screen, activity, and location collection remain deferred to their phases.
- Added capability-level exception isolation, a local caching repository,
  monitoring start/stop/refresh commands, and Flutter lifecycle integration.
- Added a random 128-bit opaque app device ID persisted in app-private
  preferences. It is not secret or authorization. Reinstall/replacement creates
  a new ID.
- Kept device observations local and separate from `PartnerDeviceState`; no
  Firestore synchronization was added. Authentication identity is attached when
  available; no active pair is needed to collect local state.
- Added platform matrix, model, architecture, freshness, background execution,
  privacy, and future payload documentation under `docs/device-state/`.

## Architecture

```text
Native APIs (future collectors)
    ↓
PlatformDeviceStateAdapter
    ↓
DeviceStateProvider
    ↓
DeviceStateSnapshot
    ↓
DeviceStateRepository (local cache)
    ↓
Riverpod/application state
    ↓
Firestore synchronization (Phase 11; deferred)
```

The current runtime adapter is intentionally unsupported for all detailed
metrics, so this phase does not report real battery/network/location values.
Flutter lifecycle resume triggers best-effort collection; inactive/paused/
detached stops observation. No periodic or post-termination execution is
claimed.

## Platform capability summary

| Capability | Android | iOS | Phase 6 runtime |
|---|---|---|---|
| Battery / charging | OS APIs exist; collectors deferred | OS APIs exist; collectors deferred | Unsupported placeholder |
| Network | Connectivity APIs exist; collector deferred | Network path API exists; collector deferred | Unsupported placeholder |
| Screen state | Limited and permission-sensitive | No general screen-state API | Unsupported placeholder |
| Activity | Own-app lifecycle observable | Own-app lifecycle observable | Unsupported placeholder |
| Location | Permissioned APIs, deferred to Phase 10 | Permissioned APIs, deferred to Phase 10 | Unsupported placeholder; no location permission added |
| Background execution | OS scheduled/opportunistic | OS scheduled/opportunistic | No scheduler; no continuous monitoring claim |

Details and platform references are in
[`device-state/PLATFORM_CAPABILITY_MATRIX.md`](device-state/PLATFORM_CAPABILITY_MATRIX.md).

## Dependencies

- `shared_preferences ^2.5.3` — stores the non-secret opaque app device ID in
  app-private preferences. The lockfile resolves version 2.5.5. No monitoring
  plugin or paid backend dependency was added.

## Tests and validation

Seven unit tests were added for partial snapshot round-trip, explicit
availability serialization, stale freshness, independent collector failure,
local cache/refresh, lifecycle controller start/stop, and device identity
generation/persistence/recovery. **Their pass/fail status is unverified.**

`flutter pub get`, `flutter analyze --no-pub`, and `flutter test --no-pub` were
started, but each remained silent beyond 30 seconds; the commands were
interrupted. Even `dart --version` did not return. The lockfile contains the
resolved direct `shared_preferences` entry, but a successful pub-get exit was
not observed. `git diff --check` completed without whitespace errors.

Android debug build and physical-device validation were not completed because
the Flutter CLI did not respond. iOS build validation is unavailable on this
Windows host (requires macOS/Xcode). No 24/7 behavior is claimed.

## Security and Spark compatibility

- No hardware identifiers, credentials, precise location, pairing secrets, or
  collected values are logged. Error logs use capability and error type only.
- The app-generated ID is not authorization. Authenticated user ownership,
  active pair consent, and Firestore Security Rules remain the future remote
  authorization boundary.
- Cloud Functions: **NOT USED**
- Cloud Run: **NOT USED**
- Paid backend: **NOT USED**
- Privileged credentials: **NONE added**

## Files changed

- `lib/core/domain/device_metric.dart`
- `lib/app/app.dart`
- `lib/features/device_state/` domain snapshot/provider/adapter/repository,
  identity persistence, unavailable adapter, Riverpod wiring, lifecycle wrapper
- `pubspec.yaml`, `pubspec.lock`
- `test/unit/device_state_foundation_test.dart`
- `docs/device-state/DEVICE_STATE_ARCHITECTURE.md`
- `docs/device-state/DEVICE_STATE_MODEL.md`
- `docs/device-state/PLATFORM_CAPABILITY_MATRIX.md`
- `docs/PHASE_06_COMPLETION_REPORT.md`

No files were deleted. Phases 7–11 collectors and synchronization remain
deferred.
