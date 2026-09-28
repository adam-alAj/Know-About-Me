# Phase 17 — Device State & Rule Event History

**Status: PARTIALLY COMPLETE.** The normalized model, bounded local history,
pair-scoped Firestore history, transition capture, history UI, dashboard preview,
and tightened rules are implemented. Acceptance items for full pagination,
broader activity/location transitions, remote automatic retention, and end-to-end
emulator verification remain open.

## Implemented

- Controlled event types/categories with UTC observed, evaluated, and server
  recorded times; privacy-minimized payload and stable opaque IDs.
- Local SharedPreferences history capped at 500 entries and 180 days, with
  deduplication, filtering, chronological ordering, malformed-item isolation,
  offline reads, and a clear-history action.
- Firestore writes to `pairs/{pairId}/events/{eventId}` only for available
  charging/connectivity transitions and meaningful rule/interpretation/alert
  decisions. Firestore update is forbidden; stable IDs prevent repeat writes.
- A history timeline with category filters and a bounded three-item dashboard
  preview.
- The configured root Firestore rules now use the strict existing pair-scoped
  ruleset, with bounded event schema/author/timestamp checks, sharing-gated
  writes, pair isolation, and owner deletion. The filtered query index was
  added to the configured root index file.
- Model unit tests and event rule test updates.

## Important files

- `lib/features/history/domain/models/device_event.dart` — event model and
  taxonomy.
- `lib/features/history/data/` — local cache and Firestore repository.
- `lib/features/history/presentation/` — providers, timeline and dashboard
  preview.
- `lib/features/rules/presentation/widgets/rule_interpretations_section.dart` —
  notification decision history integration.
- `firestore.rules` and `firebase/firestore.rules` — deployed and test rules.
- `firestore.indexes.json` — deployed history category/time index.
- `docs/history/DEVICE_STATE_AND_RULE_EVENT_HISTORY.md` — architecture, policy,
  privacy, cost and limitations.

## Data and Firestore

Remote documents contain owner, type/category, occurred/observed/recorded time,
source, opaque deduplication key, generic summary, bounded payload and schema
version. Pair and device IDs are not copied into the remote document. Writes
use server timestamps and stable document IDs; queries are bounded to 100 recent
records, optionally filtered by category.

## Privacy, retention and cost

Exact coordinates, raw samples, battery percentages, rule IDs/names and
notification body text are excluded. Local retention is 500 items / 180 days.
There is no remote scheduled cleanup; users may clear their own pair events
while connected. Each meaningful transition causes one event write; rule match,
optional interpretation, and alert decision remain separate records. No paid
Firebase service or server worker was introduced.

## Tests and validation

- `flutter analyze --no-pub`: started but produced no output for 30 seconds;
  its Dart process was stopped. No analyzer result is available.
- `dart format`: started but produced no output for 30 seconds; formatting
  remains unverified.
- `flutter test --no-pub test/unit/device_event_test.dart`: started but produced
  no output for 30 seconds; the added unit tests remain unverified.
- Firebase Emulator rules tests: not run. The Firebase CLI and Node.js are not
  available in this environment, so emulator execution and the new rule cases
  remain unverified.
- `git diff --check`: completed without whitespace errors.

## Open acceptance items

- Cursor-based history pagination beyond the first 100 entries.
- Activity, availability/stale, network transport and coarse authorized
  home/away transition event generation.
- A safe post-disconnection remote deletion flow and remote retention policy.
- Successful Flutter analysis, formatting, unit/widget tests and Firebase
  Emulator authorization tests.
