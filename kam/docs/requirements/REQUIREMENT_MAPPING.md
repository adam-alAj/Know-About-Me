# Requirement Mapping

Maps every SRS requirement to an implementation domain and the phase in which it
is planned. Requirement identifiers are the SRS identifiers
(`Docs/SRS_DOC.md`) and are not renumbered.

## Phase plan

> **Phase numbering note.** Phase 1 originally anticipated Firebase work as
> "Phase 2". The project's actual Phase 2 is **application architecture and core
> structure**, so the plan below inserts it and shifts the remaining phases by
> one. This is the authoritative numbering as of Phase 2; the phase numbers in
> the requirement tables use it.

| Phase | Focus | Status |
| --- | --- | --- |
| **1** | Foundation: project, feature structure, domain models, tests, docs | ✅ Complete |
| **2** | Application architecture: bootstrap, DI, routing shell, result/error handling, platform abstractions, shared UI, logging, architecture tests | ✅ Complete |
| **3** | Firebase project + authentication + user profile | Planned |
| **4** | Pairing, consent and connection lifecycle | Planned |
| **5** | Device monitoring (battery, charging, connectivity, availability, activity) | Planned |
| **6** | Location and home presence | Planned |
| **7** | Synchronization, current state, freshness and offline behaviour | Planned |
| **8** | Rule engine (conditions, evaluation, interpretations) | Planned |
| **9** | Reassurance dashboard | Planned |
| **10** | Notifications | Planned |
| **11** | Event history | Planned |
| **12** | Security hardening, audit, data lifecycle, localization, accessibility polish | Planned |

"Phase 1–2 status" is one of:

- **Done** — implemented and tested.
- **Model** — domain model / structure exists and is tested.
- **Shell** — placeholder UI or boundary exists.
- **Foundation** — supporting infrastructure exists (not the feature itself).
- **Planned** — not started; scheduled for a later phase.

---

## 1. Functional requirements

### Authentication and profile

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-001 User registration and authentication | `auth` + Firebase Auth | 3 | Foundation (`AuthRepository` + shell profile screen) |
| FR-002 User profile | `auth` | 3 | Model (`AppUser`) + shell screen |

### Pairing, consent and connection lifecycle

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-003 Pairing code generation | `pairing` + Cloud Functions | 4 | Model (`PairingCode`) |
| FR-004 Pairing code entry | `pairing` | 4 | Model |
| FR-005 Mutual consent | `pairing` (`Consent`, `ConsentRequest`) | 4 | Model |
| FR-006 Connection status | `pairing` (`ConnectionStatus`) | 4 | Model |
| FR-007 Mutual device visibility | `pairing` + security rules | 4–7 | Model (`Pair.partnerOf`) |

### Device state

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-008 Battery percentage | `device_state` | 5 | Model (`MetricValue<int>`) |
| FR-009 Charging state | `device_state` | 5 | Model (`ChargingState`) |
| FR-010 Charging duration | `device_state` | 5 | Model (`MetricValue<Duration>`) |
| FR-011 Battery state changes | `device_state` | 5 | Model (`DeviceEventType`) |
| FR-012 Network connectivity | `device_state` | 5 | Model (`NetworkStatus`) |
| FR-013 Offline duration | `device_state` | 5 | Model |
| FR-014 Last online time | `device_state` | 5 | Model |
| FR-015 Device availability | `device_state` (`DeviceAvailabilityState`) | 5 | Model |
| FR-016 Screen / activity state | `device_state` | 5 | Model (with `unsupported` path) |
| FR-017 Last activity timestamp | `device_state` | 5 | Model |

### Location and presence

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-018 Location permission | `location` | 6 | Planned |
| FR-019 Current / last known location | `location` (`LocationState`) | 6 | Model |
| FR-020 Location accuracy | `location` (`accuracyMeters`) | 6 | Model |
| FR-021 Location sharing control | `privacy` (category `location`) | 6 | Model |
| FR-022 Home location | `location` (`HomeLocation`) | 6 | Model |
| FR-023 Distance from home | `location` | 6 | Model |
| FR-024 At-home / away interpretation | `location` (`HomePresence`) | 6 | Model |
| FR-025 Stale location handling | `core/freshness` + `location` | 6 | Model |

### Rule engine

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-026 Rule creation | `rules` | 8 | Model (`Rule`, `RuleCondition`) |
| FR-027 Supported rule metrics | `rules` (`RuleMetric`) | 8 | Model |
| FR-028 Rule operators | `rules` (`RuleOperator`) | 8 | Model |
| FR-029 Rule actions | `rules` (`RuleActionType`) | 8 | Model |
| FR-030 User-defined probability | `rules` (`RuleAction.probabilityPercent`) | 8 | Model |
| FR-031 Rule-generated messages | `rules` + `dashboard` | 8 | Model (template only) |
| FR-032 Rule conditions | `rules` | 8 | Model |
| FR-033 Rule persistence | `rules` data layer | 8 | Planned |
| FR-034 Rule enable / disable | `rules` | 8 | Model (`Rule.enabled`) |
| FR-035 Rule editing | `rules` | 8 | Planned |
| FR-036 Rule deletion | `rules` | 8 | Planned |
| FR-037 Multiple rules | `rules` | 8 | Planned |
| FR-038 Rule precedence | `rules` + `dashboard` | 8–9 | Planned |
| FR-039 Rule cooldown | `rules` (`Rule.isCoolingDownAt`) | 8 | Model |
| FR-040 Rule re-triggering | `rules` | 8 | Model (cooldown basis) |

### Notifications

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-041 Push notifications | `notifications` + FCM | 10 | Model |
| FR-042 Notification preferences | `auth` (`NotificationPreference`) | 10 | Model |
| FR-043 Notification content | `notifications` (`AppNotification`) | 10 | Model |
| FR-044 Notification failure handling | `notifications` + `history` | 10 | Model |

### Reassurance dashboard

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-045 Partner overview | `dashboard` | 9 | Shell (route, layout, state handling) |
| FR-046 Current status summary | `dashboard` | 9 | Shell |
| FR-047 Data freshness | `core/freshness` + `core/ui` | 7 | Model (`FreshnessIndicator`) |
| FR-048 Unknown state | `device_state` (`DataAvailability`) | 5–9 | Model + shell (`DataStateView`) |

### History

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-049 Event history | `history` (`DeviceEvent`) | 11 | Model + shell route |
| FR-050 Event timestamps | `history` | 11 | Model |
| FR-051 History filtering | `history` (`EventCategory`) | 11 | Model |

### Privacy and connection control

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-052 Sharing controls | `privacy` | 6 / 12 | Model + shell |
| FR-053 Pause sharing | `privacy` (`SharingPreferences.sharingPaused`) | 6 | Model |
| FR-054 Revoke connection | `pairing` (`PairLifecycleState.revoked`) | 4 | Model |
| FR-055 Disconnect | `pairing` (`PairLifecycleState.disconnected`) | 4 | Model |
| FR-056 Permission changes | `device_state` (`MetricValue.asUnavailable`) | 5–6 | Model |

### Data management

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-057 Current state storage | `device_state` data layer | 7 | Planned |
| FR-058 Event storage | `history` data layer | 7 / 11 | Planned |
| FR-059 Data synchronization | sync layer (Firestore) | 7 | Planned |
| FR-060 Offline synchronization | sync layer | 7 | Planned |
| FR-061 Stale data protection | `core/freshness` | 7 | Model |

### Security and authorization

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-062 Authorized access | security rules + `pairing` | 4 / 12 | Model |
| FR-063 Server-side authorization | Firestore Security Rules | 12 | Planned |
| FR-064 Pair isolation | security rules + `Pair` | 4 / 12 | Model (`partnerOf`) |
| FR-065 Connection revocation enforcement | security rules | 4 / 12 | Model |
| FR-066 Secure data transmission | transport (TLS, Firebase SDK) | 7 / 12 | Planned |

### Error and edge cases

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-067 Missing permissions | `core/error` (`PermissionFailure`) | 5–6 | Model (`AppFailure`) |
| FR-068 Unsupported device capability | `device_state` + `core/domain` | 5 | Model (`DataAvailability.unsupported`, `DeviceCapabilityReport`) |
| FR-069 Background restrictions | collector design + freshness | 5 / 7 | Documented |
| FR-070 Device offline | `device_state` (last-seen only) | 5 / 7 | Model |
| FR-071 Battery optimization | collector design (WorkManager/BGTask) | 5 | Documented |
| FR-072 Reconnection | sync layer | 7 | Planned |

---

## 2. Non-functional requirements

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| NFR-001 Security | rules, transport, auth | 3–12 | Planned |
| NFR-002 Privacy | `privacy` | 6 / 12 | Model |
| NFR-003 Consent | `pairing` (`Consent`) | 4 | Model + tested |
| NFR-004 Data isolation | security rules + `Pair` | 4 / 12 | Model |
| NFR-005 Data minimization | model design (state + events) | 7 | Documented |
| NFR-006 Transparency | `dashboard` + freshness | 7–9 | Model (`DataPresentation`) |
| NFR-007 Accuracy representation | `MetricValue`, `core/freshness`, `core/ui` | 5–7 | Model |
| NFR-008 Platform compatibility | platform matrix + `PlatformInfo` | 5–6 | Foundation |
| NFR-009 Battery efficiency | collector design | 5 | Documented |
| NFR-010 Network efficiency | sync design | 7 | Documented |
| NFR-011 Responsiveness | dashboard + sync | 7–9 | Planned |
| NFR-012 Availability | Firebase + error handling | 7 | Planned |
| NFR-013 Reliability | sync + consistency | 7 | Planned |
| NFR-014 Fault tolerance | `core/error`, `core/result` | 5–7 | Foundation (`Result`, `AppFailure`) |
| NFR-015 Graceful degradation | `MetricValue` + `DataStateView` | 5 | Model |
| NFR-016 Scalability | Firestore data model | 7 | Documented |
| NFR-017 Maintainability | `lib/` structure + architecture tests | 1–2 | **Done** |
| NFR-018 Testability | `Clock`, providers, fakes, pure domain | 1–2 | **Done** |
| NFR-019 Cross-platform consistency | `DevicePlatform` + capability report | 5 | Model |
| NFR-020 Usability | `dashboard` | 9 | Shell |
| NFR-021 Reassurance-oriented UX | `dashboard` + shared UI | 9 | Shell |
| NFR-022 Interpretability | `Interpretation.basis` | 8 | Model |
| NFR-023 No false certainty | `Interpretation.isObjectiveFact` | 8 | Model + tested |
| NFR-024 Configurability | `rules`, `privacy`, `AppConfig` | 4–8 | Model |
| NFR-025 Data freshness | `core/freshness` + `FreshnessIndicator` | 7 | Model + tested |
| NFR-026 Time synchronization | `Clock`, `DateTimeUtils` (UTC) | 1–2 / 7 | Foundation + tested |
| NFR-027 Localization | message templates, `intl` | 12 | Documented |
| NFR-028 Accessibility | theme, semantics, text labels | 1–2 / 12 | Foundation |
| NFR-029 Secure configuration | `core/config` | 1–2 | **Done** |
| NFR-030 Auditability | `DeviceEvent` + rules | 11–12 | Model |
| NFR-031 Privacy after disconnection | security rules + retention | 12 | Planned |
| NFR-032 Data deletion | data lifecycle | 12 | Planned |
| NFR-033 Rule evaluation reliability | `rules` evaluator, injectable `Clock` | 8 | Planned |
| NFR-034 Duplicate event prevention | sync + rules | 8 | Planned |
| NFR-035 Event ordering | timestamps in models | 1–2 / 7 | Model |
| NFR-036 Security of location data | `location` + `privacy` | 6 / 12 | Model |
| NFR-037 Permission revocation safety | `MetricValue.asUnavailable` | 5 | Model |
| NFR-038 Background monitoring transparency | `dashboard` copy | 9 | Documented |
| NFR-039 Cloud cost efficiency | state + events model | 7 | **Design decided** |
| NFR-040 Extensibility | enum metrics, data-as-rules | 1–2 / 8 | Foundation (`DeviceMetric`) |
| NFR-041 Ethical interpretation | `ValueOrigin`, `Interpretation` | 1–2 / 8 | Model + tested |
| NFR-042 Secure pair lifecycle | `PairLifecycleState` | 4 | Model + tested |
| NFR-043 Concurrent state updates | per-user state documents | 7 | Planned |
| NFR-044 Recovery | auth + sync persistence | 7 | Planned |
| NFR-045 Observability | `core/logging` | 2 / 12 | **Foundation** (`AppLogger`) |

---

## 3. Requirements intentionally *not* satisfied in Phase 2

No requirement was silently dropped; each row has a phase. Those most at risk of
being faked are called out:

| Req | Why it is deferred, not faked |
| --- | --- |
| FR-008 – FR-017 | No native collector exists yet. `UnavailableDeviceStateSource` reports unsupported/unknown and never returns a value. |
| FR-041 | No FCM integration and no Firebase project yet. |
| FR-063 – FR-066 | Server-side authorization requires the Firebase project created in Phase 3+. |
| FR-015 / FR-070 | Powered-off detection does not exist on either platform. Only reachability + last-seen are modelled. |
| FR-016 | Continuous screen state is unavailable on iOS; modelled as `unsupported`. |
