# Software Requirements Specification (SRS)

## Mutual Phone Reassurance Application

**Version:** 1.0
**Date:** September 2026
**Platform:** Android / iOS
**Primary Technology:** Flutter
**Backend / Cloud:** Firebase

---

# 1. Project Overview

## 1.1 Project Purpose

The application is a private, consent-based mobile application designed for two people who are physically separated and want to reassure each other by sharing selected information about the current state of their mobile devices.

The application does not primarily function as a traditional messaging, social, or location-sharing application. Its main purpose is to provide a **reassurance view** based on measurable device and presence indicators.

After two users explicitly agree to connect, each user can view selected information about the other user's device, such as:

* Battery percentage
* Charging state
* Approximate charging duration
* Network connectivity
* Last time the device was online
* Last known location
* Distance from a configured home location
* Screen/device activity indicators where supported
* Last observed device activity
* Relevant device availability/state information
* Rule-generated interpretations based on observed conditions

The system must clearly distinguish between **observed device information** and **interpretations generated from user-defined rules**.

For example, if a user creates:

```text
Charging duration > 240 minutes
→ Sleep probability = 70%
```

the other user may see:

> **"There is a 70% possibility that Adam is sleeping now."**

The system must not represent such an interpretation as a confirmed fact.

---

## 1.2 Core Concept

The application consists of two connected users.

For example:

```text
User A's Phone
       │
       │ device state
       ▼
   Firebase
       │
       │ authorized sharing
       ▼
User B's Application
```

At the same time:

```text
User B's Phone
       │
       │ device state
       ▼
   Firebase
       │
       │ authorized sharing
       ▼
User A's Application
```

Therefore, the relationship is fundamentally **mutual**.

Each user can:

1. Create or join a connection.
2. Approve the connection.
3. Select what information is shared.
4. View the partner's available device state.
5. Create rules based on the partner's observable state.
6. Receive interpreted messages when rule conditions are satisfied.
7. Disconnect or revoke access.

---

## 1.3 Pairing and Consent

Users must not be able to access another person's device information without explicit authorization.

The connection process shall use a pairing mechanism, such as a temporary pairing code.

A typical flow is:

```text
User A creates pairing code
          ↓
User B enters pairing code
          ↓
User A ↔ User B connection request
          ↓
Both users authorize the relationship
          ↓
Connection becomes active
```

The pairing code itself must not constitute permanent authorization.

The application must maintain a persistent relationship only after the required consent process has been completed.

---

## 1.4 Device State Model

The application shall treat device information as **observed state**, not as absolute knowledge about the person.

For example:

```text
Battery: 82%
Charging: Yes
Network: Online
Last update: 22 seconds ago
Last known location: Home
Distance from home: 0.3 km
```

These observations may then be processed by the rule system.

Example:

```text
Charging > 240 minutes
        ↓
Rule condition satisfied
        ↓
Sleep probability = 70%
        ↓
Partner sees:

"Adam may be sleeping now (70%)."
```

The system must preserve this distinction between:

**Observed fact**

> Phone has been charging for 4 hours.

and:

**Derived interpretation**

> There is a 70% possibility that the person is sleeping.

---

## 1.5 Rule Engine Concept

Users shall be able to create rules using available device and presence metrics.

A rule consists conceptually of:

```text
IF [condition]
THEN [interpretation]
```

Example:

```text
IF charging_duration > 240 minutes
THEN sleep_probability = 70%
```

Another example:

```text
IF offline_duration > 60 minutes
THEN message = "The phone has been offline for more than an hour."
```

Another:

```text
IF distance_from_home > 5 km
THEN message = "The phone is currently more than 5 km from home."
```

Rules may produce:

* Informational messages
* Status messages
* Probability statements
* Warnings
* Presence interpretations
* Custom user-defined messages

The application must never present a user-defined probability as an objectively calculated probability unless an actual statistical/ML model is responsible for calculating it.

If the user manually defines:

```text
Charging > 240 min → 70%
```

the system should treat **70% as the user's configured interpretation**, not as a scientifically calculated probability.

---

## 1.6 Primary User Experience

The main screen should provide a simple reassurance-oriented view rather than exposing raw technical information only.

Example:

```text
─────────────────────────────
          Afraa
─────────────────────────────

🟢 Online

🔋 Battery
78%

⚡ Charging
For 2h 18m

🌐 Network
Connected

📍 Location
Near Home

🏠 Distance
0.4 km

📱 Activity
No recent activity

─────────────────────────────

😴 Possible Sleep

70%

There is a 70% possibility
that Afraa is sleeping now.

Based on:
Phone charging for more
than 4 hours.
─────────────────────────────
```

---

## 1.7 Privacy Principle

The application shall follow a **minimum necessary information** principle.

Users should only expose information that is required for their intended reassurance experience.

Examples of configurable sharing include:

* Battery
* Charging status
* Network status
* Location
* Distance from home
* Activity indicators
* Rule-generated interpretations

A user must be able to stop sharing or disconnect the relationship.

---

# 2. Functional Requirements

## FR-001 — User Registration and Authentication

The system shall allow users to create and authenticate an application account.

The authentication system shall support secure identity management through Firebase Authentication or an equivalent authentication mechanism.

The system shall maintain a unique user identifier for each account.

---

## FR-002 — User Profile

The system shall allow users to configure basic profile information.

The profile may include:

* Display name
* Profile image
* Home location
* Home location name
* Time zone
* Notification preferences
* Privacy/sharing preferences

---

## FR-003 — Pairing Code Generation

The system shall allow a user to generate a pairing code for connecting with another user.

The pairing code shall:

* Be sufficiently difficult to guess.
* Have a limited validity period.
* Be invalidated after successful use where appropriate.
* Not directly grant access to private device information.
* Be associated with the intended connection process.

---

## FR-004 — Pairing Code Entry

The system shall allow another user to enter a valid pairing code.

The system shall validate the code before creating a connection request.

Invalid, expired, already-used, or revoked codes shall be rejected.

---

## FR-005 — Mutual Consent

The system shall require explicit authorization before private device information becomes available to the other user.

The application shall clearly communicate:

* Who is requesting the connection.
* What information may be shared.
* Whether location will be shared.
* Whether device-state information will be shared.

---

## FR-006 — Connection Status

The system shall display the current relationship status.

Possible states include:

* Not connected
* Pairing pending
* Connection requested
* Connected
* Temporarily paused
* Disconnected
* Revoked

---

## FR-007 — Mutual Device Visibility

After successful authorization, each user shall be able to view the authorized device information of the connected partner.

User A shall not automatically receive access to information that User B has disabled.

The same principle shall apply in the opposite direction.

---

# Device State Requirements

## FR-008 — Battery Percentage

The application shall collect the device's current battery percentage where supported.

The displayed value shall range from:

```text
0% – 100%
```

The application shall display the approximate time of the last successful battery-state update.

---

## FR-009 — Charging State

The system shall detect the device charging state where supported.

Possible states may include:

* Charging
* Not charging
* Fully charged
* Unknown

The system shall record the time at which charging begins where technically possible.

---

## FR-010 — Charging Duration

The system shall calculate the duration for which the device has continuously been observed as charging.

Example:

```text
Charging for:
2 hours 17 minutes
```

The charging timer shall reset when the system detects that charging has stopped.

If charging state becomes unknown, the application shall not incorrectly assume that charging continued indefinitely.

---

## FR-011 — Battery State Changes

The system shall detect significant battery-state changes where supported.

Examples:

* Battery percentage increased.
* Battery percentage decreased.
* Charging started.
* Charging stopped.
* Device became fully charged.
* Battery entered a low-battery state.

---

## FR-012 — Network Connectivity

The system shall detect the device's network connectivity state where supported.

Possible states include:

* Online
* Offline
* Wi-Fi
* Mobile data
* Unknown

The system shall record the last confirmed online timestamp.

---

## FR-013 — Offline Duration

The system shall calculate the approximate duration since the device was last successfully observed online.

Example:

```text
Offline for:
47 minutes
```

If the device reconnects, the offline duration shall stop and the online timestamp shall be updated.

---

## FR-014 — Last Online Time

The application shall display the last time the device successfully communicated with the service.

Example:

```text
Last online:
11:42 PM
```

---

## FR-015 — Device Availability

The system shall maintain an availability state based on the last successful communication.

Possible states may include:

* Active / reachable
* Recently seen
* Offline
* Unknown

The system shall not claim that a phone is physically powered off merely because it is unreachable.

---

## FR-016 — Screen / Activity State

Where the operating system permits access, the application shall collect supported indicators related to device activity.

Possible states may include:

* Recently active
* No recent activity
* Screen active
* Screen inactive
* Unknown

The application shall clearly handle platforms where exact screen state cannot be continuously observed.

---

## FR-017 — Last Activity Timestamp

The system shall store the most recent supported indication of device activity.

Example:

```text
Last activity:
18 minutes ago
```

The application shall distinguish between:

* Last application activity
* Last observable device activity

when the platform provides enough information to do so.

---

# Location and Presence Requirements

## FR-018 — Location Permission

The system shall request explicit location permission before collecting location information.

The application shall explain why location is required.

The user shall be able to deny location access.

---

## FR-019 — Current / Last Known Location

Where permission and operating-system capabilities allow, the application shall obtain the device's current or most recent known location.

The system shall associate location information with a timestamp.

Example:

```text
Last known location:
Home

Updated:
3 minutes ago
```

---

## FR-020 — Location Accuracy

The system shall retain or communicate an appropriate indication of location accuracy where available.

The application shall not represent an approximate location as an exact physical position.

---

## FR-021 — Location Sharing Control

Users shall be able to enable or disable location sharing independently from other device-state information.

Disabling location sharing shall not necessarily disconnect the entire relationship.

---

## FR-022 — Home Location

The user shall be able to configure a home location.

The home location may be represented by:

* GPS coordinates
* A manually selected map location
* A user-defined place name

---

## FR-023 — Distance From Home

The system shall calculate the approximate distance between the last known device location and the configured home location.

Example:

```text
Distance from home:
3.7 km
```

The distance shall be explicitly identified as approximate when the location itself is approximate or stale.

---

## FR-024 — At-Home / Away Interpretation

The system may derive a basic presence state from location.

Possible states include:

* At home
* Near home
* Away from home
* Unknown

The user may configure the radius used to determine the home area.

---

## FR-025 — Stale Location Handling

The system shall indicate when location information is old.

Example:

```text
Location updated:
2h 13m ago
```

The application shall not present an old location as the user's current exact location.

---

# Rule Engine Requirements

## FR-026 — Rule Creation

Users shall be able to create custom rules based on available metrics.

A rule shall contain at minimum:

```text
Metric
Operator
Threshold
Action / Interpretation
```

Example:

```text
Metric:
Charging duration

Operator:
Greater than

Threshold:
240 minutes

Interpretation:
Sleep probability = 70%
```

---

## FR-027 — Supported Rule Metrics

The rule engine should support applicable metrics including:

* Battery percentage
* Charging state
* Charging duration
* Online/offline state
* Offline duration
* Last online duration
* Last activity duration
* Distance from home
* At-home/away state
* Location availability
* Location age
* Device availability
* Other supported device-state metrics

---

## FR-028 — Rule Operators

The rule engine shall support appropriate comparison operators, including:

* Equal to
* Not equal to
* Greater than
* Greater than or equal to
* Less than
* Less than or equal to
* Is
* Is not
* Has remained in state for

---

## FR-029 — Rule Actions

A rule may generate one or more supported outputs.

Examples:

* Display message
* Display status
* Display probability statement
* Trigger notification
* Change a reassurance indicator
* Create an event/history record

---

## FR-030 — User-Defined Probability

The system shall allow users to associate a manually configured percentage with a rule.

Example:

```text
Charging > 240 minutes
→ "There is a 70% possibility that the person is sleeping."
```

The application shall clearly treat the percentage as a **user-defined rule interpretation** rather than an objectively measured probability.

---

## FR-031 — Rule-Generated Messages

The system shall generate a readable message when a rule becomes active.

For example:

```text
There is a 70% possibility that Afraa
is sleeping now.
```

The message shall dynamically use the connected user's display name where permitted.

---

## FR-032 — Rule Conditions

Rules shall be evaluated against current and recent device-state data.

A rule shall become active only when its defined condition is satisfied.

---

## FR-033 — Rule Persistence

Users shall be able to save rules.

Saved rules shall remain active until:

* Disabled
* Edited
* Deleted
* The connection is removed
* Required data becomes unavailable

---

## FR-034 — Rule Enable / Disable

Users shall be able to enable or disable individual rules without deleting them.

---

## FR-035 — Rule Editing

Users shall be able to modify:

* Metric
* Operator
* Threshold
* Percentage
* Message
* Notification behavior
* Active/inactive status

---

## FR-036 — Rule Deletion

Users shall be able to permanently delete a rule.

---

## FR-037 — Multiple Rules

The system shall support multiple simultaneous rules.

Example:

```text
Charging > 60 min
→ "Charging for a long time."

Charging > 240 min
→ "70% possibility of sleeping."

Offline > 60 min
→ "Phone has been offline for more than an hour."

Distance > 5 km
→ "Phone is more than 5 km from home."
```

---

## FR-038 — Rule Precedence

When multiple rules are active simultaneously, the system shall determine how they are presented without creating contradictory or confusing messages.

The system may group related interpretations.

Example:

```text
😴 Possible Sleep — 70%

The phone has been:
• Charging for 4h 12m
• Inactive for 3h 46m
```

---

## FR-039 — Rule Cooldown

The system shall support cooldown behavior to prevent repeated notifications from the same continuously active rule.

Example:

A rule that remains true for two hours should not generate hundreds of identical notifications.

---

## FR-040 — Rule Re-Triggering

A rule may become eligible for notification again after its condition becomes false and later becomes true again, subject to its configured cooldown.

---

# Notifications

## FR-041 — Push Notifications

The application shall support push notifications for relevant rule events where the user has enabled notifications.

---

## FR-042 — Notification Preferences

Users shall be able to configure notification behavior.

Possible options include:

* All rule notifications
* Important notifications only
* No notifications
* Specific rules only

---

## FR-043 — Notification Content

Notifications shall contain concise, understandable information.

Example:

> "There is a 70% possibility that Afraa is sleeping now."

Notifications should avoid exposing unnecessary private information.

---

## FR-044 — Notification Failure Handling

If a push notification cannot be delivered, the underlying rule event shall remain available in the application history where applicable.

---

# Reassurance Dashboard

## FR-045 — Partner Overview

The main partner dashboard shall provide a concise overview of the connected person's current state.

It should include applicable:

* Online/offline state
* Battery
* Charging
* Charging duration
* Last activity
* Location
* Distance from home
* Current rule interpretations

---

## FR-046 — Current Status Summary

The system shall generate a human-readable summary of the partner's current observable state.

Example:

```text
🟢 Online
🔋 82%
⚡ Charging for 1h 24m
🏠 Near home
📱 No recent activity
```

---

## FR-047 — Data Freshness

Every time-sensitive metric shall have an associated freshness/last-updated indication where appropriate.

---

## FR-048 — Unknown State

When the system cannot determine a metric, it shall show:

```text
Unknown
```

or an equivalent message.

It shall not guess a device state.

---

# History

## FR-049 — Event History

The system shall maintain a history of important state changes and rule events where configured.

Possible events include:

* Charging started
* Charging stopped
* Device went offline
* Device came online
* Location changed significantly
* Rule activated
* Rule notification generated
* Connection changed
* Sharing permission changed

---

## FR-050 — Event Timestamps

Historical events shall contain timestamps.

---

## FR-051 — History Filtering

Users should be able to view relevant history by category, such as:

* Device
* Network
* Location
* Charging
* Rules
* Notifications

---

# Privacy and Connection Control

## FR-052 — Sharing Controls

Users shall be able to control which categories of information are shared with their connected partner.

---

## FR-053 — Pause Sharing

A user shall be able to temporarily pause sharing.

The application shall clearly indicate to the partner that information is currently unavailable because sharing has been paused, rather than falsely showing the last state as current.

---

## FR-054 — Revoke Connection

A user shall be able to revoke the connection.

After revocation, the other user shall no longer have access to newly generated private device information.

---

## FR-055 — Disconnect

Users shall be able to disconnect from their partner.

---

## FR-056 — Permission Changes

The system shall handle operating-system permission changes.

For example:

```text
Location permission revoked
        ↓
Location = unavailable
        ↓
Partner sees:
"Location unavailable"
```

The application shall not continue presenting previously known location as current.

---

# Data Management

## FR-057 — Current State Storage

The system shall maintain the latest known device state required by the application.

---

## FR-058 — Event Storage

The system shall store relevant state-change and rule events where history is enabled.

---

## FR-059 — Data Synchronization

The system shall synchronize authorized state information between the two connected users.

---

## FR-060 — Offline Synchronization

The application shall handle temporary loss of connectivity.

When connectivity is restored, the application shall synchronize applicable current state and important events.

---

## FR-061 — Stale Data Protection

The system shall distinguish between:

```text
Current
Recently observed
Stale
Unknown
```

This distinction shall be visible when necessary to avoid misleading the user.

---

# Security and Authorization

## FR-062 — Authorized Access

A user shall only be able to access information belonging to:

* Themselves
* An explicitly authorized connected partner

---

## FR-063 — Server-Side Authorization

Access control shall be enforced by backend/Firebase security rules and shall not rely solely on Flutter client-side checks.

---

## FR-064 — Pair Isolation

Data belonging to one pair shall not be accessible to another unrelated pair.

---

## FR-065 — Connection Revocation Enforcement

Once a connection is revoked, subsequent data access shall be denied.

---

## FR-066 — Secure Data Transmission

Private device information shall be transmitted using secure communication mechanisms.

---

# Error and Edge-Case Handling

## FR-067 — Missing Permissions

The application shall clearly explain when a required operating-system permission is missing.

---

## FR-068 — Unsupported Device Capability

If a device or operating system does not support a requested metric, the application shall display the metric as unavailable rather than generating a false value.

---

## FR-069 — Background Restrictions

The application shall account for mobile operating-system background execution restrictions.

When background execution prevents fresh information from being collected, the application shall expose the last update time.

---

## FR-070 — Device Offline

If the device cannot communicate with the backend, the partner shall see that the device was last observed at a specific time rather than being told that the person is definitely offline.

---

## FR-071 — Battery Optimization

The application shall handle battery optimization and operating-system restrictions that may prevent continuous background monitoring.

---

## FR-072 — Reconnection

When a device reconnects after being unavailable, the system shall update its current state and last-online information.

---

# 3. Non-Functional Requirements

## NFR-001 — Security

The system shall protect private user and device information against unauthorized access.

Authentication, authorization, database security rules, and API/cloud-service access controls shall be implemented using secure mechanisms.

---

## NFR-002 — Privacy

The application shall follow privacy-by-design principles.

Only information explicitly permitted by the user shall be shared with the connected partner.

---

## NFR-003 — Consent

The system shall require explicit user consent before establishing a persistent sharing relationship.

Consent shall not be implied merely by entering a pairing code.

---

## NFR-004 — Data Isolation

Each pair's private information shall be logically isolated from all other users and pairs.

---

## NFR-005 — Data Minimization

The system shall collect and retain only information necessary to provide the application's functionality.

---

## NFR-006 — Transparency

The application shall clearly communicate:

* What information is being collected.
* What information is being shared.
* When information was last updated.
* Whether information is unavailable.
* Whether an interpretation is based on a user-defined rule.

---

## NFR-007 — Accuracy Representation

The system shall not represent approximate, stale, inferred, or unavailable information as exact current information.

---

## NFR-008 — Platform Compatibility

The application shall support Android and iOS using Flutter while respecting the different background execution, location, battery, networking, and privacy restrictions imposed by each operating system.

---

## NFR-009 — Battery Efficiency

The application shall minimize battery consumption caused by background monitoring.

The system shall avoid unnecessary continuous polling where event-driven or appropriately scheduled mechanisms can be used.

---

## NFR-010 — Network Efficiency

The system shall minimize unnecessary network traffic and database writes.

Device state should only be synchronized when meaningful changes occur or when required to maintain an accurate current state.

---

## NFR-011 — Responsiveness

The partner dashboard should update promptly after a new valid device-state update reaches the backend.

The application shall communicate stale data instead of blocking indefinitely while waiting for a new update.

---

## NFR-012 — Availability

The cloud components shall be designed to remain available during normal operation.

Temporary connectivity failures shall not corrupt stored user relationships or rule configurations.

---

## NFR-013 — Reliability

The system shall preserve consistency between:

* User relationships
* Permissions
* Device state
* Rules
* Rule events
* Notifications

---

## NFR-014 — Fault Tolerance

Temporary failures in:

* Internet connectivity
* Firebase services
* Background execution
* Location services
* Device sensors/APIs

shall not cause the application to display fabricated device states.

---

## NFR-015 — Graceful Degradation

If a capability becomes unavailable, the rest of the application shall continue functioning where possible.

For example:

```text
Location unavailable
        ↓
Battery + charging + connectivity
remain available
```

---

## NFR-016 — Scalability

The architecture shall support expansion from an initial small number of connected pairs to a substantially larger user base without requiring a fundamental redesign.

---

## NFR-017 — Maintainability

The application shall use a modular architecture separating at minimum:

* Authentication
* Pairing
* Device monitoring
* Location
* Synchronization
* Rules
* Notifications
* User preferences
* Privacy controls

---

## NFR-018 — Testability

Core functionality shall be testable independently, including:

* Pairing
* Authorization
* Device-state processing
* Rule evaluation
* Probability/message generation
* Notification triggering
* Privacy controls
* Data synchronization

---

## NFR-019 — Cross-Platform Consistency

The user experience and data model shall remain conceptually consistent across Android and iOS.

Where a capability differs between platforms, the UI shall clearly communicate the difference.

---

## NFR-020 — Usability

The primary interface shall be understandable without requiring technical knowledge.

The user should be able to understand the partner's current state within seconds.

---

## NFR-021 — Reassurance-Oriented UX

The application shall prioritize meaningful human-readable information over raw technical metrics.

For example, instead of presenting only:

```text
charging_state = true
charging_duration = 248 minutes
```

the application should be capable of presenting:

> "The phone has been charging for more than four hours."

and, when a configured rule applies:

> "There is a 70% possibility that Adam is sleeping now."

---

## NFR-022 — Interpretability

Every rule-generated interpretation should be traceable to the condition that caused it.

Where appropriate, the application should allow the user to see:

```text
Why am I seeing this?

Charging:
4h 08m

Configured rule:
Charging > 240 minutes

Interpretation:
70% possibility of sleep
```

---

## NFR-023 — No False Certainty

The application shall avoid presenting inferred human behavior as confirmed fact.

Statements generated by user-defined rules shall use appropriate uncertainty language, such as:

* "There is a 70% possibility..."
* "This may indicate..."
* "The phone has been..."
* "Based on your configured rule..."

rather than:

* "The person is sleeping."
* "The person is definitely outside."
* "The person is definitely not using the phone."

---

## NFR-024 — Configurability

Thresholds, rules, notifications, sharing preferences, and home-location settings shall be configurable without requiring a software update.

---

## NFR-025 — Data Freshness

The system shall clearly communicate the age of time-sensitive information.

A value that has not been updated recently shall not appear indistinguishable from a freshly observed value.

---

## NFR-026 — Time Synchronization

All server-side events shall use a consistent time representation.

The application shall correctly display timestamps according to the user's configured/local time zone.

---

## NFR-027 — Localization

The architecture shall allow future support for multiple languages.

User-facing messages generated by rules shall be compatible with localization.

---

## NFR-028 — Accessibility

The application should support:

* Readable text sizes
* Adequate contrast
* Screen-reader compatible controls
* Meaningful labels
* Non-color-only status indicators

---

## NFR-029 — Secure Configuration

Sensitive credentials, Firebase configuration secrets where applicable, backend secrets, and third-party API credentials shall not be hardcoded into the source code.

---

## NFR-030 — Auditability

Security-sensitive events should be traceable, including:

* Pairing
* Consent
* Connection creation
* Connection revocation
* Permission/sharing changes
* Rule creation/modification
* Important access events

---

## NFR-031 — Privacy After Disconnection

After a connection is terminated, the application shall prevent continued access to newly generated private information.

Previously stored historical information shall be governed by the application's defined retention and deletion policies.

---

## NFR-032 — Data Deletion

The system shall support appropriate deletion of user data and relationship data according to the application's privacy policy and applicable requirements.

---

## NFR-033 — Rule Evaluation Reliability

The rule engine shall evaluate conditions deterministically according to the configured rule definitions.

For identical input state and identical rule configuration, the same rule evaluation result shall be produced.

---

## NFR-034 — Duplicate Event Prevention

The system shall prevent duplicate rule notifications caused by repeated synchronization of the same device-state event.

---

## NFR-035 — Event Ordering

Where events are received out of order due to network conditions, the system shall use timestamps/versioning or equivalent mechanisms to prevent older state from incorrectly replacing newer state.

---

## NFR-036 — Security of Location Data

Location information shall receive stronger privacy protection than ordinary non-sensitive application data because it can reveal physical movement and routines.

---

## NFR-037 — Permission Revocation Safety

If a user revokes a device permission at operating-system level, the application shall adapt without treating previously available information as continuously current.

---

## NFR-038 — Background Monitoring Transparency

The application shall clearly inform users that mobile operating systems may limit background monitoring and therefore some metrics may not always be real-time.

---

## NFR-039 — Cloud Cost Efficiency

The architecture shall minimize unnecessary Firebase reads, writes, listeners, storage, and function executions.

The system shall avoid storing high-frequency raw telemetry when a current-state model and meaningful event model can provide the required functionality.

---

## NFR-040 — Extensibility

The system shall allow future addition of new device metrics and rule types without requiring a complete redesign of the existing rule engine.

Potential future metrics may include:

* Battery temperature where available
* Device motion
* Bluetooth connectivity
* Headphone connection
* Do Not Disturb state where permitted
* Charging source/type where available
* Significant location changes
* Device orientation/activity signals
* Other platform-supported indicators

---

## NFR-041 — Ethical Interpretation

The system shall distinguish device observations from conclusions about human behavior.

Device metrics may be used to produce user-configured interpretations, but the system shall not claim that such interpretations are objectively verified facts.

---

## NFR-042 — Secure Pair Lifecycle

A pairing relationship shall have a controlled lifecycle:

```text
Created
   ↓
Requested
   ↓
Accepted
   ↓
Active
   ↓
Paused / Revoked / Disconnected
```

Invalid lifecycle transitions shall be rejected.

---

## NFR-043 — Concurrent State Updates

The system shall safely handle simultaneous state changes from both devices without corrupting either user's data.

---

## NFR-044 — Recovery

After application restart, device restart, temporary network loss, or Firebase reconnection, the application shall recover the user's authenticated identity, relationship state, configured rules, and latest valid state without requiring unnecessary re-pairing.

---

## NFR-045 — Observability

The system should provide sufficient logging and monitoring for developers to diagnose:

* Synchronization failures
* Rule evaluation failures
* Notification failures
* Authentication problems
* Permission problems
* Background execution issues
* Firebase/database errors

Logs must not expose unnecessary private information.

---

# End of SRS
