# UI/UX and Accessibility

This document describes the current Android user experience and the rules for future presentation changes. It preserves the existing Flutter, Riverpod, GoRouter, repository, synchronization, Firestore authorization, and offline/recovery architecture.

## Principles

- Show observable device facts separately from user-authored interpretations.
- Pair a value with its availability and freshness. Never infer that a device is powered off or that a person is doing something.
- Treat unknown, stale, unsupported, permission-denied, unavailable, and error states as distinct.
- Keep the experience private, calm, consent-based, and non-alarming. Color reinforces a state; labels convey it.
- Present only partner data authorized by the current connection and sharing choices.

## Design system

The app uses Material 3 with a blue-gray seed palette in `lib/app/theme/app_theme.dart`. Shared spacing and the common card radius live in `lib/core/constants/app_spacing.dart`; reusable page structure, buttons, cards, section headings, loading, error, empty, unavailable, and freshness widgets live in `lib/core/ui/widgets/`. Prefer the theme text styles and shared spacing values over local font sizes and arbitrary padding. Shared buttons and icon buttons use a 48 dp minimum target. Form borders, focus, and error states are theme-level styles.

Do not encode meaning by color alone. Stale data uses a history icon and an age/status label; failures use actionable text and retry controls where recovery is possible. Avoid fixed-height wrappers around user-controlled text and respect Android text scaling.

## Navigation

The authenticated `StatefulShellRoute` preserves four main destinations: Home, Rules, History, and Privacy. Profile is reached from the Home app-bar action. Pairing and connection management are reached contextually. Rule creation/editing is nested under Rules. Use GoRouter routes for navigation; preserve standard Android system back and gesture behavior. No notification deep-link flow is currently implemented; any future handler must re-check authentication, active membership, sharing authorization, and current data before rendering partner information.

## Dashboard hierarchy

The partner reassurance dashboard presents connection/freshness first, followed by authorized battery/charging, network, availability/activity, optional location/home summary, user-defined interpretations, sharing summary, and recent history. Partner display names are used instead of internal IDs. The local device overview is separate from partner facts. Pull-to-refresh invalidates the existing providers; widgets do not create Firestore listeners.

Facts and interpretations remain distinct. Interpretation cards introduce the content as being based on a user rule and label configured percentages as **User-defined probability**. The UI must not add AI-generated confidence or behavioral conclusions.

## Freshness and availability

Use the domain's `DataFreshness` and `CapabilityAvailability`; presentation formats them but does not define new thresholds. `FreshnessIndicator` supplies text and icon semantics. Preserve the distinction between:

- fresh/recent and stale observations (include last update age when available);
- unknown values and unsupported capabilities;
- missing/unavailable information and permission denial;
- a recoverable temporary error and a confirmed value.

Stale data remains visible only as last-known data and must not look current. Offline/recovery state is owned by the Phase 20 data model and shared connection banner. Do not turn loss of network or backend reachability into a claim that the phone is off.

## Device information and location privacy

Battery state and duration are rendered only when present in the source observation. Network presentation uses normalized transport/reachability and omits IP, SSID, BSSID, and router details. Activity and display labels report only observed Android state. Location and derived home information are shown only when the current sharing policy authorizes them; exact home coordinates are not rendered. Preserve approximate-accuracy and stale indicators supplied by the existing state.

## Rules

Rules are explicitly user-defined interpretations. The list offers create, edit, enable/disable, and confirmed deletion. The builder separates name, observed conditions, the user's interpretation, and options; validation messages are tied to the affected input. Keep validation in `RuleDraft`/domain services, and never move rule evaluation into widgets. Explain that configured probability is not measured confidence. Destructive delete must remain confirmed and name the rule in user-facing wording.

## Sharing and connection controls

Privacy settings distinguish temporary pause, category choices, disconnect, and revoke. Category switches explain what the partner can or cannot see. Pause preserves category choices; disconnect ends the current relationship; revoke permanently withdraws the relationship's sharing authorization. Unconfirmed settings are read-only until the stored state can be confirmed, preventing an unavailable read from being mistaken for a confirmed all-off choice and overwritten accidentally. Errors remain non-technical and explain that the setting was not confirmed.

## Authentication, pairing, history, and notifications

Sign-in and account creation use labelled form fields, validation, and progress/error feedback. Pairing communicates the consent requirement and connection status. History provides category filters, an explicit empty state, and confirmation before clearing. Notification permission/delivery remains subject to Android runtime and app settings; do not imply that a notification was delivered or that its payload authorizes access.

## Loading, empty, offline, and error states

Use shared loading, empty, unavailable, and error components. Empty content should explain what is absent and the relevant next step. Loading should not show placeholder values as facts. Errors should avoid exception names and Firebase codes, preserve protected-data hiding, and provide retry where retry is meaningful. Offline and stale state should explain reduced freshness without alarm language.

## Accessibility and Android interaction

- Use Material controls and their built-in semantics for labels, values, selected/checked states, and enabled/disabled states.
- Give icon-only actions a useful tooltip/accessible name. Keep visible status text in addition to icons and colors.
- Use 48 dp minimum shared button/icon-button targets. Avoid custom gesture-only interactions.
- Keep focus order aligned with reading order; associate input labels and validation with their fields.
- Use semantic summaries for complex observed-state groups and avoid announcing decorative icons as independent content.
- Respect text scaling, keyboard insets, system back, and gesture navigation. Prefer flexible/scrollable layouts over fixed-height text containers.
- Check contrast with the resolved Material 3 color scheme at runtime; this source-level review is not a substitute for Android TalkBack and large-font device testing.

## Responsive layout and performance

Common pages are centered and capped at 800 dp to avoid excessively long lines on large windows/tablets while remaining full-width on phones. Rule builder retains its narrower 640 dp form. Keep cards and rows flexible under larger text and long user-authored rule/interpretation strings. Continue using the existing Riverpod provider graph, one partner-state stream, and repository-backed operations. Avoid per-card listeners, widget polling, or evaluation work triggered by rebuilds.

## Known UX limitations

- Android is the only supported runtime target; iOS is scaffolding and is not validated.
- Automated widget tests cover selected user flows, not every screen state.
- Notification deep links are not implemented.
- TalkBack, switch access, real device contrast, text scaling, landscape, small-screen, and Android back gesture checks require device/emulator validation.
- Firebase and Flutter test/build commands may be unavailable in the current workspace environment; see the Phase 22 completion report for actual outcomes.
