# Phase 27 Completion Report — Production Build and Release Configuration

## 51.1 Executive Summary

Phase 27 is **BLOCKED**. The release configuration was inspected, a production
Internet permission gap was fixed, and environment-backed signing was added with
an explicit release artifact guard and no debug-key fallback. Release checklist
and deployment runbook were created. No Firebase deployment or release artifact
was produced. Phase 26 remains BLOCKED, the permanent package identity and
intended production Firebase project are unconfirmed, and no release signing
credentials or Android test device are available.

## 51.2 Production Environment

- `firebase.json` and `.firebaserc` select `gendersocialapp`; generated Flutter
  options and the local ignored Android client configuration identify the same
  Firebase project.
- The repository contains one selected Firebase project and no explicit separate
  development/production aliases. Whether this project is intended for
  production was not verified with its owner or Firebase Console.
- Local Android Firebase registrations include `com.example.kam` and
  `com.aj.kam`. Current Gradle uses `com.example.kam`, which is registered, but
  is still a template-style application ID.
- Authentication code implements email/password registration and sign-in.
  No password-reset or account-deletion UI/flow was found in source. Firebase
  Console provider enablement, project ownership, Firestore database availability,
  and production account settings were not remotely inspected.
- The original SRS is absent. Phase 26 acceptance remains blocked.

## 51.3 Release Configuration

| Setting | Current source configuration |
| --- | --- |
| Namespace / application ID | `com.example.kam` |
| App label | `kam` |
| Launcher artwork | Flutter template icon; production branded artwork was not found |
| Flutter version | `1.0.0+1` (version name 1.0.0, build/version code 1) |
| Firebase project in source config | `gendersocialapp`; production intent unconfirmed |
| Firebase Android app matching current ID | Present in local ignored client config; generated options point to its app ID |
| Environment | Release defaults to production; verbose logs disabled in release |
| Emulator access | Misconfigured emulator request is rejected for production/release |
| Release shrinking | Not enabled/configured |
| Release signing | Environment-backed Gradle signing; release APK/AAB task graph is rejected unless all four `KAM_RELEASE_*` signing values are provided |
| Debug signing | No debug-signing fallback in release configuration |
| Internet permission | Added to main manifest in Phase 27 for release network access |
| Other sensitive permissions | Network state, foreground coarse/fine location, Android notification permission; no background location/service |
| Backup | Disabled; XML rules also exclude app-private data from cloud backup and device transfer |
| External deep links | No custom URL/app-link filter in the main manifest; the activity only declares launcher entry. Local notification tap behavior remains device-unverified. |

The package ID, label, and version were not changed: a package identity,
branding, and production release version need owner confirmation, and changing an already
distributed package has migration consequences. Increment the build number before
the first distributed release and for each later release.

Signing inputs are read from `KAM_RELEASE_STORE_FILE`,
`KAM_RELEASE_STORE_PASSWORD`, `KAM_RELEASE_KEY_ALIAS`, and
`KAM_RELEASE_KEY_PASSWORD`. No values or keystore files were found in the checked
workspace; the current environment has no configured signing variables.

## 51.4 Firebase Deployment

Status: **BLOCKED / NOT DEPLOYED**.

`firebase.json` targets root `firestore.rules` and `firestore.indexes.json`.
SHA-256 comparison showed root and `firebase/` copies of both Rules and indexes
are byte-identical. `.firebaserc` currently defaults to `gendersocialapp`, but
that target is not confirmed as the intended production project. Firebase CLI is
unavailable in this environment, Phase 26 emulator validation is blocked, and
the project was not deployed. No production authorization test was run.

## 51.5 Build Results

- `flutter pub get`, `flutter analyze`, and `flutter test`: the latest available
  attempts in Phase 26 each produced no output within 30 seconds and were
  stopped; BLOCKED. They were not rerun after the Android-only edits in Phase 27.
- `firebase emulators:exec --only firestore "npm --prefix firebase test"`:
  could not start in Phase 26 because `firebase` is not recognized; Node/npm are
  also unavailable; BLOCKED.
- `flutter build apk --debug`: not completed in the available Flutter
  environment; BLOCKED (Phase 26 records a 30-second no-output attempt).
- `flutter build apk --release`: attempted in Phase 27; no output within 30
  seconds and stopped. Signing variables are also absent. BLOCKED.
- `flutter build appbundle --release`: NOT TESTED; no distribution channel has
  been selected.
- Artifacts produced: none.

The source records Flutter 3.44.8, Dart `^3.12.2`, Gradle 9.1.0, AGP 9.0.1,
Kotlin 2.3.20, Java bytecode target 17, and Android min/compile/target API
24/36/36. These are repository/previous-report values, not freshly verified
installed toolchain versions.

## 51.6 Installation Results

NOT TESTED. ADB failed to create `\.android` with permission denied during Phase
26. No physical device or running emulator was available; no release APK exists
to install.

## 51.7 Two-User Release Test

NOT TESTED. No release artifact, controlled test Firebase environment, test
accounts, or two connected Android devices were available.

## 51.8 Security Validation

- Phase 19 historically reports 114/114 Firestore Rules tests; Phase 27 could not
  rerun them because Firebase CLI/Node/npm are unavailable.
- Rules and index deployment copies were compared and matched byte-for-byte.
- Source retains fail-closed Firestore authorization, production-safe logging,
  and release emulator rejection as described by prior phase reports. Runtime
  release behavior was not tested.
- Search/source audit found no keystore or key-properties file in the workspace,
  and no release signing environment variable was configured. `.gitignore`
  excludes keystore formats, `key.properties`, local properties, service-account
  and Firebase Admin files.
- Source search found no `debugPrint` call or test-account/development bypass in
  app runtime code. The two `kDebugMode` uses are limited to developer error
  details and a diagnostic location display; those branches are disabled in a
  release build. This is source inspection, not a release runtime test.
- This source audit is not a production penetration/security test.

## 51.9 Privacy Validation

The main manifest uses foreground coarse/fine location and Android notification
permissions, with no background location or foreground service. Backup is
disabled and backup/transfer XML excludes app-private data. Phase 25 documents
release log redaction and omission of raw exception details. No release runtime,
notification lock-screen, permission prompt, restore, sign-out, or cache-isolation
test was possible.

## 51.10 Deployment Readiness

```text
BLOCKED
```

## 51.11 Known Limitations

- Phase 26 acceptance is BLOCKED, so production behavior is not validated.
- Flutter commands stall without output; Firebase CLI/Node/npm are unavailable;
  ADB cannot initialize its user directory.
- `gendersocialapp` is selected in the repo but production intent and Firebase
  Console configuration are unconfirmed.
- Current package ID remains `com.example.kam`; final identity, app branding,
  signing key, signing variables, and distribution channel require confirmation.
- The current launcher artwork is the Flutter template icon; no approved
  production app icon/branding was available to substitute.
- Release artifact, installation, upgrade, uninstall/reinstall, two-user, network,
  and lifecycle checks remain untested.
- No Firebase deploy, Play submission, private distribution, or production
  monitoring integration was performed.
