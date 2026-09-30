# Notifications and Rule Alerts

## Current implementation

The rule evaluation presentation flow passes eligible new matches to
`LocalNotificationService`. The default implementation uses a MethodChannel;
Android `MainActivity` creates a local `Rule alerts` notification channel and
posts a device-local notification. There is no Firebase Cloud Messaging SDK,
token registration, remote sender, or notification delivered to the partner's
device by a server. Non-Android delivery is unsupported and unvalidated.

```text
authorized partner state
  -> rule evaluation and interpretation
  -> eligibility, preference, freshness, transition and cooldown checks
  -> Android permission/channel checks
  -> local notification attempt
  -> event/history result
```

The rule engine does not deliver notifications by itself. A successful match is
not evidence of OS delivery:

```text
RULE MATCH != NOTIFICATION DELIVERED
```

Only eligible new matches are considered. Stale/unknown input, disabled rules,
preference exclusions, cooldowns, missing observations, or unavailable
permissions suppress delivery. The app records shown/suppressed outcomes when a
pair scope and signed-in owner are present. Attempt/deduplication state is
process-local, so restart-level idempotency is not guaranteed.

## Privacy and tap behavior

Android alert text is generic (`Rule alert` and “A rule you created matches
shared device state. Open the app to review it.”). Exact location, rule text,
partner name, and observed values are not placed in lock-screen text. The
notification carries the rule ID as a launch intent extra. There is no custom
URL/app-link intent filter in the manifest; the app's normal authentication and
provider routing remains in place. Tap-time authorization behavior has not been
validated on a device, so do not claim it as tested.

Android 13+ requires `POST_NOTIFICATIONS`; earlier Android versions may still
have app notifications or the channel disabled in settings. The profile flow
offers an explicit notification permission action rather than prompting on
first launch. OS delivery is best effort.

## Validation status

Notification planning and widget/unit behavior have repository tests, but the
current full Flutter suite could not run. There is no release installation or
two-user notification delivery/tap test. Phase 26/27 reports contain the actual
environment blockers. No remote push or FCM configuration is claimed.
