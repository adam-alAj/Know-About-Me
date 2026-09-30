# Documentation Index

Start with the [final project handover](project/FINAL_PROJECT_HANDOVER.md) for
the as-built architecture, data flows, privacy/security boundaries, state
semantics, and final status. The project is Android-only; current functional and
release validation remains BLOCKED.

## Project onboarding and status

- [Final project handover](project/FINAL_PROJECT_HANDOVER.md) — main maintainer
  overview and change-safety boundaries.
- [Developer setup](project/DEVELOPER_SETUP.md) — prerequisites, safe emulator
  setup, run/test/build commands.
- [Troubleshooting and maintenance](project/TROUBLESHOOTING_AND_MAINTENANCE.md)
  — common issues and operational reviews.
- [Known limitations](project/KNOWN_LIMITATIONS.md) — impact, cause, behavior,
  workaround and limitation category.
- [Phase 26 completion report](PHASE_26_COMPLETION_REPORT.md) and
  [acceptance matrix](testing/END_TO_END_ACCEPTANCE_MATRIX.md) — current E2E
  evidence and blocked journeys.
- [Phase 27 completion report](PHASE_27_COMPLETION_REPORT.md),
  [production deployment](deployment/PRODUCTION_DEPLOYMENT.md), and
  [release checklist](deployment/PRODUCTION_RELEASE_CHECKLIST.md).
- [Phase 28 completion report](PHASE_28_COMPLETION_REPORT.md) — documentation
  audit and handover outcome.

## Architecture and Firebase

- [As-built Firebase architecture](architecture/FIREBASE_ARCHITECTURE.md)
- [Firestore data model](architecture/FIRESTORE_DATA_MODEL.md)
- [Current authorization and Security Rules](security/SECURITY_AND_AUTHORIZATION.md)
- [Spark compatibility](SPARK_COMPATIBILITY_CHECKLIST.md) and
  [Spark-only architecture](architecture/SPARK_ONLY_ARCHITECTURE.md)
- [Authentication architecture](architecture/AUTHENTICATION_ARCHITECTURE.md)
- [Pairing system](pairing/PAIRING_SYSTEM.md)
- [Historical Phase 1–4 architecture snapshot](architecture/ARCHITECTURE.md)
- [Architecture decision records](decisions/README.md)

## Device state, reliability and privacy

- [Device-state model](device-state/DEVICE_STATE_MODEL.md)
- [Device-state architecture](device-state/DEVICE_STATE_ARCHITECTURE.md)
- [Current Android capability contract](platform/PLATFORM_CAPABILITIES.md)
- [Android compatibility and limits](platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md)
- [Offline, stale data and recovery](reliability/OFFLINE_STALE_DATA_AND_RECOVERY.md)
- [Privacy and sharing lifecycle](privacy/PRIVACY_SHARING_AND_CONNECTION_LIFECYCLE.md)
- [Location and home distance](device-state/LOCATION_HOME_DISTANCE.md)
- [Battery/charging](device-state/BATTERY_CHARGING.md),
  [network](device-state/NETWORK_MONITORING.md), and
  [activity/availability](device-state/ACTIVITY_AVAILABILITY.md)

## Rules, interpretation, history and UI

- [Rule engine foundation](rules/RULE_ENGINE_FOUNDATION.md)
- [Rule evaluation and interpretations](rules/RULE_EVALUATION_AND_INTERPRETATIONS.md)
- [Rule builder and management](rules/RULE_BUILDER_AND_MANAGEMENT.md)
- [Notifications and rule alerts](notifications/NOTIFICATIONS_AND_RULE_ALERTS.md)
- [History model](history/DEVICE_STATE_AND_RULE_EVENT_HISTORY.md)
- [Partner dashboard](ui/PARTNER_REASSURANCE_DASHBOARD.md)
- [UI/UX and accessibility](ui/UI_UX_AND_ACCESSIBILITY.md)

## Testing and operations

- [Test strategy](testing/TEST_STRATEGY.md)
- [Manual Android test matrix](testing/MANUAL_ANDROID_TEST_MATRIX.md)
- [Performance and Firebase cost](performance/PERFORMANCE_AND_COST_OPTIMIZATION.md)
- [Observability/error handling](observability/OBSERVABILITY_ERROR_HANDLING_AND_PRODUCTION_HARDENING.md)
- [Requirements mapping](requirements/REQUIREMENT_MAPPING.md) — historical plan;
  original SRS is not present in this checkout.
- [Phase 19 Security Rules report](PHASE_19_COMPLETION_REPORT.md) — historical
  test evidence, not a current rerun.
- [Phase 21 Android report](PHASE_21_COMPLETION_REPORT.md),
  [Phase 22 UI report](PHASE_22_COMPLETION_REPORT.md),
  [Phase 23 test report](PHASE_23_TEST_REPORT.md),
  [Phase 24 performance report](PHASE_24_COMPLETION_REPORT.md), and
  [Phase 25 hardening report](PHASE_25_COMPLETION_REPORT.md).

