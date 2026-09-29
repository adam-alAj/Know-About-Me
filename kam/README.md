# Know About Me (`kam`)

A private, consent-based reassurance app for two people who are physically separated. It shows an authorized view of observed device state and user-defined rule interpretations. It is not a messaging, social, or tracking app.

## Project status

The repository contains the Phase 20 offline and stale-data implementation and Phase 21 Android compatibility hardening changes. Runtime validation for these phases is still outstanding in the current environment. See the [Phase 21 completion report](docs/PHASE_21_COMPLETION_REPORT.md).

Android is the only supported runtime target. The `ios/` directory and generated iOS Firebase options remain scaffolding; iOS runtime collection is not implemented or validated. See the [Android compatibility and limitations](docs/platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).

The backend targets the Firebase Spark plan and does not require Cloud Functions or Cloud Run. See [Spark-only architecture](docs/architecture/SPARK_ONLY_ARCHITECTURE.md) and the [Spark compatibility checklist](docs/SPARK_COMPATIBILITY_CHECKLIST.md).

## Requirements

- Flutter 3.44.8 (repository configuration; use `flutter --version` to check the installed SDK)
- Dart `^3.12.2`
- Android SDK and JDK 17 for Android builds
- Node.js and Firebase CLI only for Firestore rules and emulator tests

## Getting started

```bash
flutter pub get
flutter run
```

Useful commands:

```bash
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed .
flutter build apk --debug
```

## Firebase configuration

Configuration is supplied with `--dart-define` (see [configuration strategy](docs/decisions/ADR-004-configuration-strategy.md) and [Firebase architecture](docs/architecture/FIREBASE_ARCHITECTURE.md)):

```bash
flutter run --dart-define=APP_ENV=development --dart-define=ENABLE_VERBOSE_LOGGING=true
```

Required Firebase values must be supplied together. With no values, remote reads remain explicitly unavailable. Firebase options are provided by the app; a committed `google-services.json` is not required.

Never place server credentials in `--dart-define`; client values are public by construction.

## Architecture

The app is organized by feature under `lib/features/`, with shared services under `lib/core/`. Feature code uses domain, data, and presentation layers; domain code remains pure Dart. Tests and architecture checks are under `test/`. Android native code is under `android/`.

## Known limitations

- No live Firebase project is configured in this checkout, so remote reads are unavailable without compile-time Firebase settings.
- Android collectors are best effort while the app process is active. Background execution can be delayed or stopped by Android and device manufacturers.
- Location collection is foreground-only; background location and continuous background collection are not implemented.
- Charging duration is process-local and is not preserved across app restarts.
- Analysis, test, APK build, and device validation for Phase 21 remain pending; see the [completion report](docs/PHASE_21_COMPLETION_REPORT.md).

## Key documentation

- [Architecture](docs/architecture/ARCHITECTURE.md)
- [Security and authorization](docs/security/SECURITY_AND_AUTHORIZATION.md)
- [Privacy and sharing lifecycle](docs/privacy/PRIVACY_SHARING_AND_CONNECTION_LIFECYCLE.md)
- [Offline, stale data, and recovery](docs/reliability/OFFLINE_STALE_DATA_AND_RECOVERY.md)
- [Platform capabilities](docs/platform/PLATFORM_CAPABILITIES.md)
- [Android compatibility and limitations](docs/platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md)
- [Requirements mapping](docs/requirements/REQUIREMENT_MAPPING.md)
