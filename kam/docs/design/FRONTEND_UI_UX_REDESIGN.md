# Frontend UI/UX redesign

A quality pass over the existing Flutter frontend. It changes **presentation
only**: the backend, Firestore model, Security Rules, providers, repositories and
domain semantics are untouched, and every state distinction the app already makes
(`UNKNOWN ≠ FALSE`, `STALE ≠ CURRENT`, `NOT SHARED ≠ UNAVAILABLE`, no update ≠
phone off) is preserved in the new wording.

Measured results are in
[`../PHASE_FRONTEND_UI_UX_COMPLETION_REPORT.md`](../PHASE_FRONTEND_UI_UX_COMPLETION_REPORT.md).

---

## 1. Audit

The application is a two-person reassurance product, not a monitoring dashboard.
Its screens and the problems found:

| Screen | Purpose | Primary problem found |
| --- | --- | --- |
| Splash / sign in / create account | Identity | Long explanatory copy; uses the shared primitives already, not restructured here |
| Pairing / consent | Issue and redeem a code, both members consent | Flow correct and explicit; copy is denser than the rest of the product |
| Reassurance (dashboard) | Partner state at a glance | **Wall of cards**; the most important answers (who, reachable?, how fresh?) were buried under a technical header line and repeated freshness/"cached" strings; a full-screen loader replaced content on every refresh; verbose sentences |
| This device (dashboard section) | Local observations | Raw debug-style line dumps ("Freshness: …", "Coordinates: …") |
| Rules / rule builder | Define interpretations | Functional; reads as syntax rather than a sentence |
| History | What happened | Functional |
| Privacy / sharing | What is shared, connection control | Already simplified in the earlier cleanup pass; home location gained a map picker |
| Notifications | Local rule alerts | Copy already concise |
| Global connection strip | State of *this* connection | Correct behaviour, but "Offline" used the error palette, which reads as a failure rather than a fact |

Two structural problems drove most of the perceived quality gap:

1. **Hierarchy.** Every fact was presented with equal weight, in its own card.
2. **Nervous realtime.** A manual refresh (or any invalidation) dropped the
   provider back to loading, so the whole partner area flashed to a spinner.

---

## 2. Design system

### Spacing (`core/constants/app_spacing.dart`)

`4 · 8 · 16 · 24 · 32`, plus `xxl = 40` for between-section separation on long
screens. Values are unchanged, so existing layouts did not move.

### Radius (`AppRadius`)

A deliberate three-step scale replaces per-widget numbers:

| Token | Value | Used for |
| --- | --- | --- |
| `AppRadius.sm` | 8 | controls, status pills |
| `AppRadius.md` | 12 | cards, dialogs, text fields (the historical `AppSpacing.radius`) |
| `AppRadius.lg` | 16 | large surfaces (the map viewport) |

### Semantic colour and status tones (`StatusTone`)

Colour is expressed by **meaning**, not by widget name. Four tones map onto
Material 3 container pairs, so they stay correct in any scheme (including a
future dark theme) with no hard-coded hex values:

| Tone | Meaning | Example |
| --- | --- | --- |
| `neutral` | a plain fact | "Unknown", "Not shared" |
| `positive` | confirmed good | "Online" |
| `attention` | worth noticing, not a failure | "Offline", "Last known", "Stale" |
| `critical` | a failure, or something the user must act on | "Permission required" |

`attention` exists specifically so a dropped connection is **not** rendered in
the error palette. The product must reassure, not alarm.

### Typography

The M3 `TextTheme` is used through semantic roles so system text scaling keeps
working: `titleLarge` (partner name / screen hero), `titleMedium` (section
title), `titleSmall` (emphasised value), `bodyMedium` (values and prose),
`bodySmall` (supporting line), `labelMedium` (status pill). Nothing outside the
dashboard's local debug row uses a hard-coded size.

### Elevation

Cards keep `elevation: 0` with a 1px `outlineVariant` border. Hierarchy comes
from spacing, typography and borders — not shadows.

---

## 3. Shared primitives

| Component | Replaces | Why |
| --- | --- | --- |
| `StatusPill` (`core/ui/widgets/status_pill.dart`) | ad-hoc status containers | One visual and semantic language for every status; icon + word, never colour alone; optional `liveRegion` for genuine transitions |
| `SectionCard` + `StateRow` (`core/ui/widgets/section_card.dart`) | the dashboard's private `_StateCard` / `_StateRow` | Groups related facts into a few meaningful sections; the label is quieter than the value so a section is scanned rather than read; each row announces "Label: value" to assistive technology |
| `SectionSkeleton` / `SkeletonBox` / `SkeletonLine` (`core/ui/widgets/skeleton.dart`) | full-screen spinners | Calm, **static** placeholders that mirror the loaded layout. Deliberately not animated: a pulsing block competes with realtime updates |

Existing primitives (`AppCard`, `AppButton`, `AppInlineMessage`, `EmptyView`,
`ErrorView`, `LoadingView`, `UnavailableView`, `FreshnessIndicator`,
`DataStateView`) were kept — they were already the right abstraction and already
accessible.

---

## 4. Dashboard redesign

The screen now answers five questions in order, with explicit hierarchy.

**1 — Who, and how current.** The partner header is now: avatar, name, a
`StatusPill` for reachability, and one `FreshnessIndicator`. The technical
`Device state: Fresh` line, the "Partner device update time unknown" string and
the duplicated cached-connection sentences are gone.

Reachability wording is chosen so it can never be read as a statement about the
person: `Online`, `Last known`, `No update yet`, `Permission required`,
`Not shared`, `Unsupported`, `Unknown` — never "their phone is off".

**2 — The shared state, grouped.** Six equal cards became four meaningful
sections plus one:

| Before | After |
| --- | --- |
| Device availability | folded into the header (its one unique value, *Last online*, moved to Connection) |
| Battery & charging | **Battery** (Charge, Charging, Charging duration) |
| Network | **Connection** (Connectivity, Last online) |
| Activity indicators | **Screen and activity** (Screen, Activity, Last activity) |
| Location & home | **Location and home** (unchanged semantics, tidier labels, map action footer) |
| Sharing & privacy | **Sharing** (Status, Categories) with the manage action as its footer |

Sections the partner does not share are not rendered at all — they are never
shown as an empty card.

**3 — What the user can do.** The manage-connection action now lives in the
Sharing section footer instead of floating at the end of the page.

**4 — Interpretations and history** only render while a pair is active (there is
nothing to interpret without one).

**5 — This device** stays at the bottom, under a clear "This device" heading,
because the screen exists to answer questions about the partner.

The local device cards (`ActivitySummaryCard`, `LocationSummaryCard`, battery,
network) now use the same `SectionCard`/`StateRow` presentation. Their raw
debug-style line dumps were reorganised into labelled rows, and the redundant
"Freshness: Fresh" line was removed (the age is already shown).

---

## 5. Data states

Every state keeps its own words; none of them collapses into "N/A":

`Available · Loading · Stale · Unknown · Not shared · Permission required ·
Unsupported · Temporarily unavailable · Location off`.

Loading changed shape: instead of a full-screen spinner, a section renders a
**skeleton that keeps its real heading**, so the layout does not shift when the
value arrives.

---

## 6. Realtime behaviour

The dashboard no longer flashes on change. `_PartnerContent` keeps the previous
value on screen whenever the provider `hasValue`, even while a refresh is in
flight:

```text
first load        → skeleton (heading preserved)
refresh/reconnect → previous values stay, they update in place
genuine failure   → error panel
```

A single minute timer advances the "Updated 4 min ago" ages without touching
remote state. Realtime updates change the affected rows only; scroll position and
the rest of the screen are untouched.

---

## 7. Accessibility

- Every status is **icon + word**. Colour is reinforcement, never the only
  carrier of meaning — including the connection strip, which now uses the calm
  `attention` band instead of the error palette.
- `StateRow` exposes `Label: value` and `StatusPill` exposes its label as a
  semantic node, so a screen reader gets the pairing rather than two loose words.
- Interactive targets: `IconButton` has a tooltip and a 48dp minimum; the
  `NavigationBar` keeps standard destinations.
- Text scaling: all type comes from `TextTheme`, so system scaling applies.
- Skeletons are `ExcludeSemantics` — decorative, and announced as loading by the
  content that replaces them.
- The partner header reads as one semantic group ("<name>, partner").

---

## 8. Navigation

Unchanged, deliberately. Five primary destinations plus profile already answer
"where am I / where can I go". No destination was added for the new map picker:
it is nested under Privacy and pushes above the shell, returning to where it was
opened.

---

## 9. Known limitations and remaining work

This pass is an incremental quality pass, not a rewrite of every screen.

- **Auth, pairing, rules, history** were reviewed but not restructured. They
  already consume the shared primitives, so they inherit the tokens, tones and
  typography, but their per-screen information hierarchy and copy have not had
  the same treatment as the dashboard.
- **The rule builder still reads as a form**, not as a sentence. Making a rule
  read naturally ("When charging for more than 4 hours → …") is a worthwhile
  follow-up; it must not change the rule engine.
- **No dark theme.** The app has none today, and building a half-verified dark
  theme was explicitly out of scope. The tokens are expressed through
  `ColorScheme`, so a future dark theme is a matter of supplying a scheme.
- **The map picker's tiles** come from the public OpenStreetMap servers (see
  `docs/device-state/LOCATION_HOME_DISTANCE.md`).
- Manual on-device visual review (overflow, RTL, large-font, landscape) still has
  to be performed on hardware.
