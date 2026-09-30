# Test Strategy and Validation Boundaries

## Scope and source of truth

This strategy validates the implemented Android application and its Firebase Spark-compatible client. Security Rules remain the authorization boundary. UI tests do not substitute for emulator rule tests; emulator tests do not substitute for Android permission/lifecycle or two-user tests. The SRS is at `../..` (`Docs/SRS_DOC.md`); active security, offline, Android capability, architecture, and UI contracts are linked below.

Some earlier phase artifacts are missing from this checkout. Available completion reports are phases 1–4, 6, 17, 19, 21, and 22. Reports for phases 5, 7–16, 18, and 20 were not found. Do not infer validation results from missing reports.

## Test layers

1. **Unit tests** (`test/unit/`): deterministic domain and mapping logic, including authentication, pairing, device-state normalization, freshness, location/home calculations, rule evaluation, notification eligibility, repository behavior, and cleanup.
2. **Widget tests** (`test/widget/`): routing, authentication screens, dashboard, rules, rule builder, interpretation, history/data state, and selected privacy interactions. The latest user-provided full run discovered 663 tests, with 662 passing and one privacy-screen test failing before the latest test edits. The corrected test has not been rerun.
3. **Architecture tests** (`test/architecture/`): domain import boundaries and Spark-only architecture.
4. **Firebase Security Rules tests** (`firebase/test/firestore.rules.test.js`): run in the Firestore emulator via `firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"`. Always pass the isolated `demo-kam` project; `.firebaserc` defaults to `gendersocialapp`. The Phase 19 report records 114/114 passing historically; Phases 23/26/28 could not rerun the suite here.
5. **Android build and manual testing**: debug APK build, permissions, OS lifecycle, accessibility, layout, device-state APIs, and background constraints require the Android SDK/Flutter toolchain plus emulator or physical device.
6. **Two-user end-to-end testing**: requires two independent signed-in accounts/devices and a configured Firebase test environment. It cannot be inferred from unit/widget tests.

## Local environment recorded for this audit

- Windows OS version API: `10.0.26200.0` (Windows 11 build family).
- Dart CLI: 3.12.2 stable, Windows x64.
- Flutter SDK path: `C:\flutter`; SDK metadata in the Phase 21 report records Flutter 3.44.8. Flutter commands in this audit produced no output for 30 seconds and were stopped, so command-level SDK verification is blocked.
- Android SDK root is not configured in the process environment. `C:\platform-tools\platforms` contains android-33, android-34, android-35, and android-36. Repository config uses compile/target SDK 36 and min SDK 24.
- Gradle wrapper: 9.1.0; Android Gradle Plugin: 9.0.1; Kotlin: 2.3.20; Android Java/Kotlin target: 17.
- Installed Java: Eclipse Temurin OpenJDK 21.0.11. Build compatibility has not been validated.
- Firebase CLI, Node.js, npm, and emulator/device inventory are unavailable through PATH or ADB in the recorded workspace. ADB previously failed creating its `.android` user directory.
- Physical Android devices, emulator images, Firebase emulator version, and two-user accounts: not available/verified.

## Required commands and interpretation

Run from the Flutter package root:

```powershell
flutter pub get
flutter analyze
flutter test
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
flutter build apk --debug
```

Record exact exit code, output, test counts, and tool versions. A timed-out or unavailable command is **BLOCKED**, never PASS. Current Phase 23 outcomes are in `../PHASE_23_TEST_REPORT.md`.

## Security, privacy, and offline validation

Use Firebase emulator tests for cross-pair and malformed-write denial, ownership, consent, sharing, and closed-schema rules. Do not weaken assertions or rules to obtain green results. Test offline revocation with two independently scoped clients: cached data cannot prove current authorization; revalidate protected operations after reconnect. Keep network reachability, Firebase request success, device availability, and power state distinct. Verify local history and caches remain user-scoped through sign-out and account changes.

## Android device and accessibility validation

Use `MANUAL_ANDROID_TEST_MATRIX.md` on API 24 and API 33+ where available. Record model, OS/API, app build, permissions, network conditions, exact steps, expected and observed result, and evidence. Exercise large text, TalkBack, focus order, 48 dp targets, portrait/landscape, keyboard, system back, background suspension, force-stop, restart, and Settings permission changes. Do not claim an unrun scenario.

## Limitations

The Phase 23 audit could not execute Flutter commands, Firebase emulator tests, an Android build, an Android device matrix, or a two-user flow because the required tools/devices are blocked or absent. The historical baselines (617 Flutter tests, 114 security scenarios) are references only. The latest supplied Flutter log reports 663 total with one failed privacy widget test before the latest source edits; current full-suite status is unknown.
