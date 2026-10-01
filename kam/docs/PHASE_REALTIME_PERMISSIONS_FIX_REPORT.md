# Realtime and permission recovery fix report

**Date:** 2026-10-02  
**Status:** **INCOMPLETE — code changes made; validation blocked**

## 1. Original symptoms

The reported state could remain many hours old and manual refresh did not
meaningfully update it. The brief also called out misleading permission-required
status and missing permission recovery behavior.

## 2. Root causes and findings

- **Manual refresh:** confirmed source defect. The dashboard awaited a fresh
  native snapshot but discarded it, then reasserted the older snapshot remembered
  by the sync coordinator. The Firestore and partner listener code otherwise
  uses the existing realtime path and authorization scope.
- **Realtime:** source architecture is event-driven and has Firestore snapshot
  listeners with metadata changes, stream error forwarding, authorization-based
  provider recreation, and bounded sync retry. No production listener/backend
  trace was available to establish a separate runtime break.
- **Permissions:** Android's location status check tests fine or coarse grant
  first and separately reports fine-grant precision. The normal monitoring start
  on app resume re-reads status. Source inspection did not confirm a false
  “permission required” result for a granted permission.
- **Recovery action:** a permanently denied location state had explanatory text
  but no settings button. The card now opens Android app settings and tells the
  user to enable approximate or precise location.
- **Rules/cache/timestamps:** no rule changes made. State observation time,
  Firestore synchronization time, cache metadata, and stale classification remain
  distinct. Deployed Firebase project/rules could not be inspected.

Detailed flow and source findings are in
[`BUGFIX/ROOT_CAUSE_REALTIME_AND_PERMISSIONS.md`](BUGFIX/ROOT_CAUSE_REALTIME_AND_PERMISSIONS.md).

## 3. Changes made

- `DeviceStateSyncCoordinator.publishNow()` now remembers the snapshot it is
  asked to publish; `reconcileNow()` provides the explicit refresh/reconcile
  entry point through that same existing sync service.
- Dashboard pull-to-refresh now passes its newly collected native snapshot to
  `reconcileNow()` before refreshing the authorized partner streams.
- Location gateway and collector expose an app-settings action; Android opens
  `ACTION_APPLICATION_DETAILS_SETTINGS`; the permanent-denial card presents the
  missing location grant and “Open app settings”.
- Added unit coverage for the coordinator's fresh reconciliation and a test fake
  implementation for the settings gateway method.
- No polling, paid backend, new Firebase service, fake timestamp, or Firestore
  Security Rules change was introduced.

## 4. Validation results

| Requested command | Result |
| --- | --- |
| `flutter pub get` | **BLOCKED** — no output for 90 seconds; stopped. |
| `flutter analyze` | **BLOCKED** — no output for 30 seconds; stopped. |
| `flutter test` | **BLOCKED** — no output for 30 seconds; stopped. |
| `firebase emulators:exec --only firestore "npm --prefix firebase test"` | **BLOCKED** — `firebase` command not found. |
| `flutter build apk --debug` | **BLOCKED** — no output for 30 seconds; stopped. |
| `flutter build apk --release` | **BLOCKED** — no output for 30 seconds; stopped. |

No current passing test counts are claimed. Historical Phase 19/28 counts are
not treated as evidence for this change.

## 5. Two-device and permission checks

| Scenario | Result |
| --- | --- |
| Device A state change reaches Device B without refresh | **NOT RUN** — physical devices unavailable. |
| Manual refresh publishes current Android state | **NOT RUN on device** — code path fixed; automated run blocked. |
| Background and resume reconciliation | **NOT RUN on device**. |
| Revoke, grant in Settings, return without restart | **NOT RUN on device**. |
| Offline recovery and sharing revocation | **NOT RUN on device**. |

## 6. Remaining limitations

The app can report only while Android lets its process execute. An offline
device cannot publish until network returns. The current workspace did not
provide runnable Flutter/Firebase tooling output or physical devices, so the
success criteria are not fully verified. Production/deployed project selection
and Security Rules were not checked remotely.
