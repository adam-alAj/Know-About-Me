# Partner Reassurance Dashboard

## Purpose and structure

The Reassurance destination presents only device observations shared by an
active partner. It shows the pair-scoped partner name when available, connection
state, observation freshness, device availability, and the battery, charging,
network, activity, location, and home-distance categories the partner enabled.
It does not infer sleep, safety, attention, or other human behavior.

The screen reuses `AppScaffold`, `AppCard`, `AppInlineMessage`, the application
theme, spacing scale, and Riverpod providers. Its content is a responsive
scrolling list and supports text scaling. State labels are text, not color-only
indicators; approximate location accuracy is retained and displayed. Exact
coordinates and home coordinates are never rendered. Existing local battery,
network, activity, location, and sync summaries remain available below the
partner section, including when no pair is active.

## Data flow and state management

```text
Authenticated membership stream
  -> active PartnerScope
  -> partner sharing stream (fail closed)
  -> authorized Phase 11 partner state stream
  -> presentation-only formatting
  -> dashboard cards
```

The repository owns Firestore listeners. Pair or account changes replace the
scope, which disposes the old partner-state listener. The dashboard does not
query Firestore or poll. A local one-minute clock tick refreshes relative-time
and freshness labels only; it performs no network reads.

The partner display name is read only from
`pairs/{pairId}/members/{partnerUid}`. On consent, the pairing repository copies
the user's display name into that pair-scoped record; later profile edits update
the active pair's display-name copy. Private `users/{uid}` profiles are never
queried for the partner.

## Presentation and privacy

- Overall freshness uses `RemoteDeviceState.observationFreshnessAt` and the
  existing standard freshness policy. Observation time is distinct from online
  time and synchronization time. Cached values are explicitly marked.
- Battery percentage and charging details appear only for enabled categories;
  charging duration appears only when charging and a duration is known.
- Network shows the normalized shared network observation and the partner's
  last confirmed online time. Firestore connectivity is not treated as device
  connectivity.
- Activity and screen values appear only when activity sharing is enabled.
  Last activity is called “Last observable activity.”
- Location is shown only when the location category is active. The UI shows age,
  approximate precision/accuracy, and derived distance/home status only when
  those categories are enabled. A stale fix is labelled last-known and its home
  status is not presented as current.
- A paused, missing, or unreadable sharing record hides partner details. A
  pending, disconnected, revoked, or missing pair shows an appropriate
  connection state and does not render the old partner state.
- Cached pair or sharing settings are labelled as last known; they are not
  treated as proof that access is still active while offline.
- Empty, loading, and error states are distinct. Retry invalidates the existing
  stream provider rather than starting a polling loop.

## Offline behavior and limitations

Firestore-cached state remains visible with its age and a cached-data notice.
The dashboard does not currently identify the viewer's offline condition
separately from Firestore cache metadata. Pair records created before this phase
may not yet have a member display-name document; in that case the UI uses the
generic “Your partner” label until the record is populated. The app's available
platform collectors determine which metrics can be published; unsupported or
unavailable values remain explicit rather than being fabricated.

Accessibility uses semantic labels, normal text scaling, and text-based state
descriptions. There is no map or coordinate display. Manual two-account,
revocation, and real-device location tests require configured Firebase accounts
and devices and were not run as part of local automated validation.

## Phase boundary

This screen is a facts-only presentation layer. Rules, interpretations,
notifications, background alerting, and server-side processing are deferred to
Phases 13–16. Firebase Spark-only constraints remain in force.
