# Know About Me

A private, consent-based **Mutual Device Presence & Reassurance** mobile app.
Two people who are separated explicitly connect their devices; each can then see
a limited, authorized view of the other's **observed device state** (battery,
charging, connectivity, last online, activity, and location where permitted) plus
**interpretations** produced by rules they define themselves.

The app never presents a user-defined interpretation as a fact, and never shows
stale or unavailable information as current.

## Repository layout

| Path | Contents |
| --- | --- |
| `kam/` | The Flutter application (all source, tests and app documentation) |
| `kam/firebase/` | Firestore Security Rules, indexes and their emulator tests |
| `Docs/SRS_DOC.md` | Software Requirements Specification — the primary source of truth |

## Start here

- Application README: [`kam/README.md`](kam/README.md)
- Phase 1 completion report: [`kam/docs/PHASE_01_COMPLETION_REPORT.md`](kam/docs/PHASE_01_COMPLETION_REPORT.md)
- Phase 2 completion report: [`kam/docs/PHASE_02_COMPLETION_REPORT.md`](kam/docs/PHASE_02_COMPLETION_REPORT.md)
- Phase 3 completion report: [`kam/docs/PHASE_03_COMPLETION_REPORT.md`](kam/docs/PHASE_03_COMPLETION_REPORT.md)
- Architecture: [`kam/docs/architecture/ARCHITECTURE.md`](kam/docs/architecture/ARCHITECTURE.md)
- Firebase foundation: [`kam/docs/architecture/FIREBASE_ARCHITECTURE.md`](kam/docs/architecture/FIREBASE_ARCHITECTURE.md)
- Firestore data model: [`kam/docs/architecture/FIRESTORE_DATA_MODEL.md`](kam/docs/architecture/FIRESTORE_DATA_MODEL.md)
- Firebase security model: [`kam/docs/architecture/FIREBASE_SECURITY.md`](kam/docs/architecture/FIREBASE_SECURITY.md)
- Platform capability matrix: [`kam/docs/platform/PLATFORM_CAPABILITIES.md`](kam/docs/platform/PLATFORM_CAPABILITIES.md)
- Requirement mapping: [`kam/docs/requirements/REQUIREMENT_MAPPING.md`](kam/docs/requirements/REQUIREMENT_MAPPING.md)
- Architecture decisions: [`kam/docs/decisions/`](kam/docs/decisions/)

## Quick start

```bash
cd kam
flutter pub get
flutter analyze
flutter test
flutter run
```

Requires Flutter 3.44.x (Dart 3.12.x). The app runs without a Firebase project:
Firebase initializes only when project identifiers are supplied via `--dart-define`,
and otherwise the app runs offline with explicit non-available states.

To exercise the Firestore Security Rules (no Firebase account needed):

```bash
cd kam
firebase emulators:exec --only firestore "node --test firebase/test/firestore.rules.test.js"
```

## Status

**Phases 1 (foundation), 2 (application architecture) and 3 (Firebase backend
foundation) are complete.** The project builds for Android, analyzes cleanly, its
Flutter tests pass, and the Firestore Security Rules are proven by 31 emulator
tests. Authentication, pairing, device monitoring, location, the rule engine and
notifications are scheduled in later phases — see the phase plan in the
requirement mapping.

Two things are deliberately incomplete and documented rather than faked: no real
Firebase project is connected (Phase 4 supplies credentials), and no Cloud
Functions project exists yet (Phase 5 needs it to activate a pair). No privileged
credential and no project-specific config file is committed.
