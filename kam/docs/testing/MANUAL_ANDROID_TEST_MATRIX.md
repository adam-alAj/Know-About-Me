# Manual Android Test Matrix

All result cells start as **NOT TESTED** unless evidence is recorded below. Required coverage is API 24 and API 33+; API 33+ is important for runtime notification permission. This workspace did not have a usable ADB device/emulator, so no row is claimed as executed.

| Area | Scenario | Expected behavior | Actual result | Status | Evidence to record |
| --- | --- | --- | --- | --- | --- |
| Install | Fresh install on API 24 | App starts; no permission crash | No device available | BLOCKED | Device/API, build, startup log |
| Install | Fresh install API 33+ | App starts and asks permissions only in context | No device available | BLOCKED | Device/API, screenshots |
| Auth | Create account, sign in, restore session | Auth state and routing are correct | Not exercised on device | NOT TESTED | Accounts redacted, steps, result |
| Pairing | A creates invitation; B accepts | Pair remains pending until both consent; then active | No two-user environment | BLOCKED | Emulator logs and pair lifecycle |
| Pairing | Reject, cancel, expire, reuse code | Correct terminal state; expired/reused code denied | No two-user environment | BLOCKED | Code lifecycle evidence |
| Consent | One-sided consent | Pair is not active | No two-user environment | BLOCKED | Pair documents before/after |
| Authorization | Cross-pair access attempt | Denied by Security Rules | Emulator suite not run here | BLOCKED | Emulator test output |
| Battery | 0, 1, 20, 50, 99, 100 percent | Values normalized accurately | No device available | NOT TESTED | Battery level and UI capture |
| Charging | Plug/unplug/full/reconnect/app already charging | Accurate status; no invented duration/start time | No device available | NOT TESTED | Event timeline and app state |
| Network | Wi-Fi/mobile/offline/Internet unavailable | Transport, reachability, Firebase, and availability remain distinct | No device available | NOT TESTED | Network transition timeline |
| Screen/activity | Lock, unlock, app foreground/background | Only supported observations shown; no behavior inference | No device available | NOT TESTED | API, state output, screenshots |
| Location | Deny, approximate, precise, revoke, restore in Settings | UI reflects permission and recovers without reinstall | No device available | BLOCKED | Permission choices and results |
| Location privacy | Disable location sharing / revoke pair | Partner view hides protected location | No two-user environment | BLOCKED | Sharing and partner-view screenshots |
| Home/distance | Below, equal, above configured threshold | Existing domain boundary behavior rendered | No device available | NOT TESTED | Threshold and exact test distances |
| Synchronization | Device A updates; B observes | Authorized fields/timestamps arrive; no duplicate listener | No two-user environment | BLOCKED | Firestore emulator logs and B screen |
| Change tracking | Repeat identical battery/network/location/activity state | Existing coordinator avoids unnecessary duplicate writes | No instrumentation environment | NOT TESTED | Read/write counters/logs |
| Offline | B caches A state then loses network; A revokes | Offline client does not claim revocation knowledge; protected operations revalidate after reconnect | No two-user environment | BLOCKED | Both clients' timeline and emulator logs |
| Staleness | Fresh, recent, stale, unknown, unavailable values | Distinct labels; stale never presented as current | Widget coverage only; device check absent | NOT TESTED | Screenshots and source timestamps |
| Rules | Operator boundaries, AND/OR, cooldown, stale/unknown input | Follows deterministic domain semantics | Unit suite not rerun in this audit | NOT TESTED | Rule fixtures and evaluation output |
| Notifications | Permission denied, allowed, cooldown, duplicate trigger | No delivery claim when permission denied; no duplicate alert | No device available | NOT TESTED | OS setting, event log, notification tray |
| History | Clear history and account switch | Owner-scoped history; no cross-account local leak | Device check absent | NOT TESTED | Account-switch steps and records |
| Sharing | Category off, pause, resume, disconnect, revoke | Controls and authorized partner view agree | Privacy widget tests not rerun | NOT TESTED | Both screens and rule authorization |
| Lifecycle | Background, Doze, force-stop, relaunch, reboot | Delayed observations become stale/unknown; never imply powered-off | No device available | BLOCKED | Device/API, timestamps, lifecycle logs |
| Accessibility | TalkBack, switch labels, focus traversal | Critical state understandable without color alone | No device available | BLOCKED | TalkBack recording/notes |
| Layout | Small/normal/large phone, landscape, large font, keyboard | No clipping, overflow, or inaccessible control | No device available | BLOCKED | Screen dimensions, font scale, screenshots |
| Android back | System button/gesture, dialog, nested rule editor | Natural route and dialog dismissal behavior | No device available | BLOCKED | Navigation trace |
| Performance/cost | Startup, dashboard rebuilds, listener count, writes | No polling, duplicate listeners, telemetry spam, or avoidable repeated writes | No profiler/emulator run | NOT TESTED | Flutter/Firestore profiling evidence |
| End-to-end | Full two-device scenario in Phase 23 prompt | All authorized state, rule, notification, history, pause/resume, revoke behavior correct | No devices/accounts | BLOCKED | Step-by-step signed-off run record |

## Result entry template

For each executed row, append: date/time, tester, device/model, Android version/API, app commit/build, preconditions, exact steps, expected result, observed result, status, and evidence location. Redact account identifiers and location data.
