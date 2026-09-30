# Requirement Mapping

> **Handover note:** The phase plan and Phase 1–2/Phase 2 requirement status
> tables below are historical planning snapshots, not a current feature-status or
> release-validation report. Later phases implemented pairing, Android device
> collectors, location, rules, notifications, history and privacy controls.
> Current implementation/status is summarized in
> [`../project/FINAL_PROJECT_HANDOVER.md`](../project/FINAL_PROJECT_HANDOVER.md).
> The referenced original SRS (`Docs/SRS_DOC.md`) is not present in this checkout.

> **Platform contract:** Android is the only supported runtime target. iOS and
> other non-Android targets are unsupported and unvalidated. See
> [Android compatibility](../platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).

Maps every SRS requirement to an implementation domain and the phase in which it
is planned. Requirement identifiers are the SRS identifiers
(`Docs/SRS_DOC.md`) and are not renumbered.

## Phase plan

> **Phase numbering note.** The delivered phases are the Project Owner's briefing
> phases, which split the original plan differently: briefing Phase 2 was
> application architecture (not Firebase), briefing Phase 3 was the Firebase
> **foundation only**, and authentication was moved into briefing Phase 4. The
> table below is the authoritative numbering; the phase numbers in the requirement
> tables use it, and earlier tables were re-phased accordingly in Phase 4.

| Phase | Focus | Status |
| --- | --- | --- |
| **1** | Foundation: project, feature structure, domain models, tests, docs | ✅ Complete |
| **2** | Application architecture: bootstrap, DI, routing shell, result/error handling, platform abstractions, shared UI, logging, architecture tests | ✅ Complete |
| **3** | Firebase foundation: FlutterFire integration, environment strategy, Firestore data model, Security Rules + emulator tests | ✅ Complete |
| **4** | Authentication and user profile: registration, sign-in, sign-out, session restoration, guarded routing, profile documents | ✅ Complete |
| **4b** | **Spark-only correction**: removed the Cloud Functions dependency, moved activation/codes to Security Rules and rule evaluation to client logic; documented local notification boundary and deferrals | ✅ Complete |
| **5** | Pairing, consent and connection lifecycle | Planned — the backend capability now exists (rules + both-consent activation), so no server work blocks it |
| **6** | Device monitoring (battery, charging, connectivity, availability, activity) | Planned |
| **7** | Location and home presence | Planned |
| **8** | Synchronization, current state, freshness and offline behaviour | Planned |
| **9** | Rule engine (conditions, evaluation, interpretations) | Partly done early: the **evaluator** exists (`RuleEvaluator`, Spark migration); the rule *management* UI is planned |
| **10** | Reassurance dashboard | Planned |
| **11** | Notifications | Planned |
| **12** | Event history | Planned |
| **13** | Security hardening, audit, data lifecycle, localization, accessibility polish | Planned |

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
| FR-001 User registration and authentication | `auth` + Firebase Auth | 4 | **Implemented**: register/sign-in/sign-out, session restoration, guarded routes; 222 Flutter tests |
| FR-002 User profile | `auth` + Firestore `users/{uid}` | 4 | **Implemented**: create/read/update display name + private preferences, ownership enforced by rules (16 emulator tests) |

### Pairing, consent and connection lifecycle

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-003 Pairing code generation | `pairing` (client CSPRNG) + Security Rules (`pairingCodes`) | 5 | **Foundation**: rules enforce length, ≤1 h expiry, single-use and `list` denial (7 emulator tests) |
| FR-004 Pairing code entry | `pairing` | 5 | Model |
| FR-005 Mutual consent | `pairing` (`Consent`, `ConsentRequest`) | 5 | Model |
| FR-006 Connection status | `pairing` (`ConnectionStatus`) | 5 | Model |
| FR-007 Mutual device visibility | `pairing` + security rules | 5–8 | Model (`Pair.partnerOf`) |

### Device state

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-008 Battery percentage | `device_state` | 6 | Model (`MetricValue<int>`) |
| FR-009 Charging state | `device_state` | 6 | Model (`ChargingState`) |
| FR-010 Charging duration | `device_state` | 6 | Model (`MetricValue<Duration>`) |
| FR-011 Battery state changes | `device_state` | 6 | Model (`DeviceEventType`) |
| FR-012 Network connectivity | `device_state` | 6 | Model (`NetworkStatus`) |
| FR-013 Offline duration | `device_state` | 6 | Model |
| FR-014 Last online time | `device_state` | 6 | Model |
| FR-015 Device availability | `device_state` (`DeviceAvailabilityState`) | 6 | Model |
| FR-016 Screen / activity state | `device_state` | 6 | Model (with `unsupported` path) |
| FR-017 Last activity timestamp | `device_state` | 6 | Model |

### Location and presence

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-018 Location permission | `location` | 7 | Planned |
| FR-019 Current / last known location | `location` (`LocationState`) | 7 | Model |
| FR-020 Location accuracy | `location` (`accuracyMeters`) | 7 | Model |
| FR-021 Location sharing control | `privacy` (category `location`) | 7 | Model |
| FR-022 Home location | `location` (`HomeLocation`) | 7 | Model |
| FR-023 Distance from home | `location` | 7 | Model |
| FR-024 At-home / away interpretation | `location` (`HomePresence`) | 7 | Model |
| FR-025 Stale location handling | `core/freshness` + `location` | 7 | Model |

### Rule engine

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-026 Rule creation | `rules` | 9 | Model (`Rule`, `RuleCondition`) + **evaluator** (`RuleEvaluator`) |
| FR-027 Supported rule metrics | `rules` (`RuleMetric`) | 9 | Model |
| FR-028 Rule operators | `rules` (`RuleOperator`) | 9 | Model |
| FR-029 Rule actions | `rules` (`RuleActionType`) | 9 | Model + interpretations built by the evaluator |
| FR-030 User-defined probability | `rules` (`RuleAction.probabilityPercent`) | 9 / 15 | Model + **evaluated**: the engine renders "There is a N% possibility…" and the dashboard shows it as an explicitly labelled *user-defined* percentage, never as a measurement |
| FR-031 Rule-generated messages | `rules` + `dashboard` | 9 / 15 | **Built**: `InterpretationBuilder` maps an evaluation to the user's own wording, `RuleInterpretationsSection` shows it on the reassurance dashboard |
| FR-032 Rule conditions | `rules` | 14 | **Built**: type-safe metric/operator/value builder derived from the engine's metric catalogue, with ALL/ANY grouping |
| FR-033 Rule persistence | `rules` data layer | 14 | **Built**: `RuleRepository` + `FirestoreRuleRepository` (`users/{uid}/rules`), owner-scoped and validated in the domain layer before saving |
| FR-034 Rule enable / disable | `rules` | 14 | **Built**: enable/disable from the list and the builder; the evaluator never runs a disabled rule |
| FR-035 Rule editing | `rules` | 14 | **Built**: whole-rule draft → validation → atomic update; id stable, version increments; exact-duplicate detection |
| FR-036 Rule deletion | `rules` | 14 | **Built**: confirmed deletion that names the rule; disabled rules are never auto-deleted |
| FR-037 Multiple rules | `rules` | 14 | **Built**: list, create and edit any number of rules, newest first |
| FR-038 Rule precedence | `rules` + `dashboard` | 9–10 | **Not implemented**: `RuleAction` has no priority field, so all matching rules are shown (deterministically ordered) rather than ranked |
| FR-039 Rule cooldown | `rules` (`Rule.isCoolingDownAt`) | 9 / 15 | Model + **evaluator + UI**: a cooling-down match keeps its interpretation, stays visible, and reports `isNewMatch == false` |
| FR-040 Rule re-triggering | `rules` | 9 / 15 | **Built**: `RuleTransition` (`becameMatched` / `stayedMatched` / `becameNotMatched` / indeterminate) so a continuously satisfied rule is never re-reported as new |

### Notifications

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-041 Push notifications | `notifications` + FCM | 11 | **Foundation**: `LocalNotificationService` + `RuleNotificationPlanner` (local delivery). Remote push is **deferred** — it needs a trusted sender the Spark plan cannot host |
| FR-042 Notification preferences | `auth` (`NotificationPreference`) | 4 | **Stored and editable** (profile → private settings); delivery belongs to Phase 11 |
| FR-043 Notification content | `notifications` (`AppNotification`) | 11 | Model |
| FR-044 Notification failure handling | `notifications` + `history` | 11 | **Foundation**: the owner-written record survives a failed delivery; `delivered` is an explicit flag |

### Reassurance dashboard

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-045 Partner overview | `dashboard` | 10 / 15 | Shell (route, layout, state handling) + **rule interpretations** with observed facts and "why this matched" |
| FR-046 Current status summary | `dashboard` | 10 / 15 | Shell + **rule-based interpretation** of the currently authorized state |
| FR-047 Data freshness | `core/freshness` + `core/ui` | 8 / 15 | Model (`FreshnessIndicator`) + **used per interpretation**, with a stale basis labelled rather than hidden |
| FR-048 Unknown state | `device_state` (`DataAvailability`) | 6–10 / 15 | Model + shell (`DataStateView`) + **evaluation**: unknown, stale, unsupported and permission-denied inputs are never reported as matches |

### History

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-049 Event history | `history` (`DeviceEvent`) | 12 | Model + shell route |
| FR-050 Event timestamps | `history` | 12 | Model |
| FR-051 History filtering | `history` (`EventCategory`) | 12 | Model |

### Privacy and connection control

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-052 Sharing controls | `privacy` | 7 / 13 | Model + shell |
| FR-053 Pause sharing | `privacy` (`SharingPreferences.sharingPaused`) | 7 | Model |
| FR-054 Revoke connection | `pairing` (`PairLifecycleState.revoked`) | 5 | Model |
| FR-055 Disconnect | `pairing` (`PairLifecycleState.disconnected`) | 5 | Model |
| FR-056 Permission changes | `device_state` (`MetricValue.asUnavailable`) | 6–7 | Model |

### Data management

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-057 Current state storage | `device_state` data layer | 8 | Planned |
| FR-058 Event storage | `history` data layer | 8 / 12 | Planned |
| FR-059 Data synchronization | sync layer (Firestore) | 8 | Planned |
| FR-060 Offline synchronization | sync layer | 8 | Planned |
| FR-061 Stale data protection | `core/freshness` | 8 | Model |

### Security and authorization

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-062 Authorized access | security rules + `pairing` | 5 / 13 | Model |
| FR-063 Server-side authorization | Firestore Security Rules | 13 | Planned |
| FR-064 Pair isolation | security rules + `Pair` | 5 / 13 | Model (`partnerOf`) |
| FR-065 Connection revocation enforcement | security rules | 5 / 13 | Model |
| FR-066 Secure data transmission | transport (TLS, Firebase SDK) | 8 / 13 | Planned |

### Error and edge cases

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| FR-067 Missing permissions | `core/error` (`PermissionFailure`) | 6–7 | Model (`AppFailure`) |
| FR-068 Unsupported device capability | `device_state` + `core/domain` | 6 | Model (`DataAvailability.unsupported`, `DeviceCapabilityReport`) |
| FR-069 Background restrictions | collector design + freshness | 6 / 8 | Documented |
| FR-070 Device offline | `device_state` (last-seen only) | 6 / 8 | Model |
| FR-071 Battery optimization | collector design (WorkManager/BGTask) | 6 | Documented |
| FR-072 Reconnection | sync layer | 8 | Planned |

---

## 2. Non-functional requirements

| Req | Domain | Phase | Phase 1–2 status |
| --- | --- | --- | --- |
| NFR-001 Security | rules, transport, auth | 3–13 | Planned |
| NFR-002 Privacy | `privacy` | 7 / 13 | Model |
| NFR-003 Consent | `pairing` (`Consent`) | 5 | Model + tested |
| NFR-004 Data isolation | security rules + `Pair` | 5 / 13 | Model |
| NFR-005 Data minimization | model design (state + events) | 8 | Documented |
| NFR-006 Transparency | `dashboard` + freshness | 8–10 | Model (`DataPresentation`) |
| NFR-007 Accuracy representation | `MetricValue`, `core/freshness`, `core/ui` | 6–8 | Model |
| NFR-008 Platform compatibility | platform matrix + `PlatformInfo` | 6–7 | Foundation |
| NFR-009 Battery efficiency | collector design | 6 | Documented |
| NFR-010 Network efficiency | sync design | 8 | Documented |
| NFR-011 Responsiveness | dashboard + sync | 8–10 | Planned |
| NFR-012 Availability | Firebase + error handling | 8 | Planned |
| NFR-013 Reliability | sync + consistency | 8 | Planned |
| NFR-014 Fault tolerance | `core/error`, `core/result` | 6–8 | Foundation (`Result`, `AppFailure`) |
| NFR-015 Graceful degradation | `MetricValue` + `DataStateView` | 6 | Model |
| NFR-016 Scalability | Firestore data model | 8 | Documented |
| NFR-017 Maintainability | `lib/` structure + architecture tests | 1–2 | **Done** |
| NFR-018 Testability | `Clock`, providers, fakes, pure domain | 1–2 | **Done** |
| NFR-019 Cross-platform consistency | `DevicePlatform` + capability report | 6 | Model |
| NFR-020 Usability | `dashboard` | 10 | Shell |
| NFR-021 Reassurance-oriented UX | `dashboard` + shared UI | 10 | Shell |
| NFR-022 Interpretability | `Interpretation.basis` | 9 | Model |
| NFR-023 No false certainty | `Interpretation.isObjectiveFact` | 9 | Model + tested |
| NFR-024 Configurability | `rules`, `privacy`, `AppConfig` | 5–9 | Model |
| NFR-025 Data freshness | `core/freshness` + `FreshnessIndicator` | 8 | Model + tested |
| NFR-026 Time synchronization | `Clock`, `DateTimeUtils` (UTC) | 1–2 / 8 | Foundation + tested |
| NFR-027 Localization | message templates, `intl` | 13 | Documented |
| NFR-028 Accessibility | theme, semantics, text labels | 1–2 / 13 | Foundation |
| NFR-029 Secure configuration | `core/config` | 1–2 | **Done** |
| NFR-030 Auditability | `DeviceEvent` + rules | 12–13 | Model |
| NFR-031 Privacy after disconnection | security rules + retention | 13 | Planned |
| NFR-032 Data deletion | data lifecycle | 13 | Planned |
| NFR-033 Rule evaluation reliability | `rules` evaluator, injectable `Clock` | 9 | Planned |
| NFR-034 Duplicate event prevention | sync + rules | 9 | Planned |
| NFR-035 Event ordering | timestamps in models | 1–2 / 8 | Model |
| NFR-036 Security of location data | `location` + `privacy` | 7 / 13 | Model |
| NFR-037 Permission revocation safety | `MetricValue.asUnavailable` | 6 | Model |
| NFR-038 Background monitoring transparency | `dashboard` copy | 10 | Documented |
| NFR-039 Cloud cost efficiency | state + events model | 8 | **Design decided** |
| NFR-040 Extensibility | enum metrics, data-as-rules | 1–2 / 9 | Foundation (`DeviceMetric`) |
| NFR-041 Ethical interpretation | `ValueOrigin`, `Interpretation` | 1–2 / 9 | Model + tested |
| NFR-042 Secure pair lifecycle | `PairLifecycleState` | 5 | Model + tested; activation gated in the rules by **both** consent documents |
| NFR-043 Concurrent state updates | per-user state documents | 8 | Planned |
| NFR-044 Recovery | auth + sync persistence | 8 | Planned |
| NFR-045 Observability | `core/logging` | 2 / 13 | **Foundation** (`AppLogger`) |

---

## 3. Requirements intentionally *not* satisfied in Phase 2

No requirement was silently dropped; each row has a phase. Those most at risk of
being faked are called out:

| Req | Why it is deferred, not faked |
| --- | --- |
| FR-008 – FR-017 | No native collector exists yet. `UnavailableDeviceStateSource` reports unsupported/unknown and never returns a value. |
| FR-041 | Notification planning has a local boundary (`RuleNotificationPlanner` + `LocalNotificationService`), but the default service reports unsupported until a platform plugin is added. No FCM registration or sending path exists. Remote push needs a trusted sender, and the Spark plan cannot host one — deferred, not faked (ADR-009). |
| FR-063 – FR-066 | Authorization is enforced by Firestore Security Rules — the Firebase project is configured (Phase 3) and the rules are tested (70 emulator scenarios). There is no server-side component: the rules *are* the enforcement point. |
| FR-015 / FR-070 | Powered-off detection does not exist on either platform. Only reachability + last-seen are modelled. |
| FR-016 | Continuous screen state is unavailable on iOS; modelled as `unsupported`. |
