# Notifications and Rule Alerts (Phase 16)

## Architecture

`RuleEvaluationController` consumes authorized partner state and enabled rules,
then emits Phase 15 `InterpretationResult` values. `RuleNotificationPlanner`
applies the existing global preference, match, indeterminate and canonical
cooldown decisions. The dashboard presentation listens for new transitions and
passes an eligible alert to `LocalNotificationService`. The service crosses a
MethodChannel to Android or iOS and cannot send to another device.

```text
authorized state → existing rule engine → interpretation/transition
  → planner and permission gate → local OS notification
```

The notification layer does not evaluate conditions. Unknown, unavailable,
stale or missing evidence is not alerted. Disabled rules are excluded by the
existing evaluation pipeline and checked again before delivery. Only
`becameMatched` transitions are considered; repeated matches are not delivered
again. The engine's configured cooldown is authoritative.

## Preferences, permission, and privacy

The existing private `UserPreferences.notificationPreference` supports all,
important only, selected rules only, or none. Important/selected modes currently
have no rule selection UI, so the planner suppresses rules unless the caller
explicitly supplies an eligible rule set; no importance is inferred.

The profile screen offers an explicit **Enable device notifications** action.
Permission is never requested at launch. Android 13+ uses
`POST_NOTIFICATIONS`; the app remembers that a request was made and does not
repeat a permanently denied prompt. Earlier Android versions are treated as
granted. iOS uses `UNUserNotificationCenter` authorization. A denied user can
change the setting in OS Settings.

Lock-screen title/body are deliberately generic. The notification payload
contains only the rule ID. Exact location, home location, observed values,
interpretation text, names and probabilities are not sent to the OS alert text.
No FCM SDK, token registration, server sender, Functions, Cloud Run, Scheduler,
Pub/Sub, Admin SDK, server credential or paid Google Cloud service is used.

## IDs, duplicate handling, and taps

The request ID is derived from rule ID, rule version and the Phase 15 evaluation
fingerprint (or evaluation timestamp fallback). Android replaces the same
integer-ID notification; iOS uses the request identifier. A process-local set
prevents repeated delivery attempts for the same key during the active process.
This is not a durable notification history and may reset when the app process
restarts.

Tapping opens the app through the OS launch intent. The payload is currently
not routed to a specific rule screen; the user sees the normal authenticated
app and can review current rule results. Deleted rules and revoked pairs cannot
be used to fetch or reveal additional content from a notification.

## Lifecycle and platform limits

Rule evaluation runs when the app has an active evaluation consumer and receives
state or its bounded in-process timer fires. It does not run in a background
service, after process termination, or on another user's phone. While the app is
backgrounded, already posted Android/iOS notifications may be displayed by the
OS; no new rule evaluation is promised. Returning to the app resumes normal
evaluation. Foreground presentation is enabled on iOS. Android uses a default
importance channel named **Rule alerts** and the app icon.

Pair revocation removes authorized partner state; the evaluation provider stops
and clears its transition history. No new partner alert can be generated from
that state. No automatic cross-device push is available under the Firebase
Spark-only design. Future cross-device delivery requires a trusted, secured and
funded server sender and a separate architecture/security review; client FCM
credentials must never be embedded in Flutter.

## Validation

Pure planner tests and local-service contract tests remain the unit-level
strategy. Android emulator/device and iOS device/simulator checks are needed for
real OS permission dialogs, channel settings, banners, taps and denied states.
This environment did not expose a usable Flutter command during this phase, so
those platform acceptance checks are not claimed as performed.
