# Phase 21 Completion Report — Android Compatibility and Platform Hardening

**PHASE 21 STATUS: BLOCKED**

The source audit and hardening changes are prepared, but Phase 21 cannot be marked complete because Flutter analysis/tests, Android build, and device/emulator checks could not be completed in the available environment. Phase 20's required runtime validation also remains an unverified baseline.

## Scope and outcome

Phase 21 focuses on Android compatibility, permissions, device APIs, backup behavior, and documentation. Android is now explicitly the sole supported runtime target. iOS project files and generated Firebase options remain as scaffolding and are not evidence of iOS support.

## Changes made

- Restricted platform detection and device-state collectors to Android; non-Android platforms report unsupported capability.
- Replaced the screen-interactivity proxy with the default display's explicit display state.
- Made notification permission reporting honor Android 13 runtime permission and app-level notification settings on all supported API levels; added a dedicated small notification icon.
- Persisted location permission request/grant history so a revoked or expired one-time grant is not mistaken for a current grant; permanent denial remains recoverable through Settings guidance.
- Disabled cloud backup and configured Android backup/device-transfer exclusions for app data.
- Removed the redundant Google Services Gradle plugin because Firebase options are supplied explicitly by the app.
- Updated and added tests for non-Android unsupported behavior and wrote the Android compatibility matrix and manual validation scenarios.

## Compatibility contract

Configured values: min SDK 24, compile/target SDK 36, AGP 9.0.1, Gradle 9.1.0, Kotlin 2.3.20, JVM 17, NDK 28.2.13676358; local Flutter SDK observed as 3.44.8, with Dart `^3.12.2`. See [Android compatibility and limitations](platform/ANDROID_COMPATIBILITY_AND_LIMITATIONS.md).

## Acceptance checklist

- [x] Android-only runtime support is explicit; non-Android device collectors return unsupported.
- [x] Permissions and API-dependent notification behavior were reviewed and adjusted.
- [x] Location remains foreground-only; background location and foreground-service permissions are absent.
- [x] Backup exclusions cover app data containing local state.
- [x] Capability limits, privacy considerations, and manual device scenarios are documented.
- [ ] `flutter analyze` completed successfully.
- [ ] Unit and widget tests completed successfully.
- [ ] Debug Android APK build completed successfully.
- [ ] Android API 24 and API 33+ emulator/device manual matrix completed.
- [ ] Phase 20 acceptance validation completed successfully.

## Validation results

| Check | Result |
| --- | --- |
| Flutter SDK/version command | Blocked: Flutter process did not produce output in the allotted wait. Version is recorded from the locally installed SDK metadata. |
| `flutter analyze` | Blocked: command produced no output for 30 seconds and was stopped. |
| Flutter tests | Blocked: command produced no output for 30 seconds and was stopped. |
| Debug APK build | Blocked: command produced no output for 30 seconds and was stopped. |
| Android emulator/device | Not completed; ADB could not initialize `\.android` (`Cannot mkdir '\\.android': Permission denied`), including after setting `ANDROID_USER_HOME`. |
| Firebase CLI validation | Not available; Firebase CLI and Node/npm were not on PATH. |
| Manual API-level matrix | Not completed. |

No test, build, or device result is claimed as passing. The API configuration and platform behavior claims above come from source inspection, not a completed build or device run.

## Remaining work

Run analysis, tests, and `flutter build apk --debug` with a working Flutter/Android toolchain. Then execute the manual scenarios on API 24 and API 33+ and resolve any failures. Revalidate the Phase 20 acceptance criteria before treating this phase as complete.
