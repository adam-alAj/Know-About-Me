# ADR-006 — State scoping and the async data-presentation contract

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 2

## Context

The SRS requires the UI to distinguish loading, loaded, empty, unknown,
unsupported, unavailable, stale and failed states, and to never show an
unavailable metric as a value (FR-048, FR-056, FR-061, FR-068, NFR-007, NFR-015,
NFR-025). It also requires that a failure in one part of the app does not break
another (NFR-015, NFR-014).

Phase 2 additionally had to decide how state is scoped (Task 7: ephemeral UI state
vs application/domain state) and discovered a concrete Riverpod 3 hazard while
implementing the profile screen.

## Decision

### 1. Two explicitly separated state scopes

- **Ephemeral UI state** (selected tab, dialog visibility, form fields, local
  loading flags) lives in the widget or in a screen-scoped provider. The
  navigation shell owns its selected branch.
- **Application/domain state** (current user, connection state, partner device
  state, rules, location, history) is owned by providers that wrap a
  repository/source.

There is **no single global application-state object**. Each concern gets its own
provider so one failing concern cannot freeze others.

### 2. One presentation vocabulary, resolved in one place

`DataPresentationState` = `loading | empty | loaded | failure | unknown |
unsupported | unavailable | paused`, carried by `DataPresentation`, rendered
exhaustively by `DataStateView`.

Freshness is intentionally **not** a state. A stale value is still a value, so
stale is a property of loaded data, shown by `FreshnessIndicator` as
"Last updated 2h 13m ago" and only secondarily by colour. Modelling stale as a
state would tempt screens to hide the last known value entirely, which is less
useful and not what the SRS asks for.

### 3. Mapping happens through `PresentationMapping`, never `AsyncValue.when`

In Riverpod 3 an `AsyncValue` keeps `isLoading` set while also holding an error —
the two flags are independent. `AsyncValue.when` therefore calls `loading` and
**silently hides an error that has already arrived**. This was observed directly:
a stream that emits an error produced `AsyncLoading` *with* an error attached, and
the profile screen showed "Checking account…" instead of the failure.

`PresentationMapping.fromAsync` / `fromAsyncResult` check `hasValue` first, then
`hasError`, then fall back to loading:

```
hasValue            → loaded (or the classified Result failure)
else hasError       → failure(AppFailure.fromException(error).message)
else                → loading
```

Screens must use these helpers rather than `when`. This is covered by a unit test
(`test/unit/presentation_mapping_test.dart`) that reproduces the loading+error
case.

## Consequences

Positive:

- Every screen handles all eight states through one widget, so a state cannot be
  forgotten per screen.
- An error is never masked by a spinner, and internals are never displayed.
- The device-data honesty rules (unknown vs 0%, stale vs current) are enforced
  centrally by `DataStateView` and `MetricTile` rather than by convention.
- New async data sources plug into an existing contract.

Negative / accepted trade-offs:

- Screens that need the value itself (for example the profile screen) still read
  the `AsyncValue` directly, because `DataPresentation` only carries the state.
  Those screens replicate the `hasValue → hasError → loading` ordering; the
  ordering rule is documented in the code next to it.
- `DataPresentation` carries no generic payload. Adding one would make the shared
  widget harder to reuse than the small duplication it would remove.

## Alternatives considered

- **Use `AsyncValue.when` everywhere.** Rejected: demonstrably hides errors in
  Riverpod 3.
- **A generic `AsyncState<T>` wrapper of our own.** Rejected: duplicates
  `AsyncValue` and adds a layer for no behaviour we do not already have.
- **A single global app-state object.** Rejected: one failing concern would affect
  unrelated screens, and it conflicts with the "no false certainty" principle by
  encouraging a single blended view of the data.
- **Modelling stale as a `DataPresentationState`.** Rejected as described above;
  freshness is a property of the value, not a replacement for it.
