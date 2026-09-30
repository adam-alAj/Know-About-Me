# Production Deployment Procedure

This procedure is a release runbook, not evidence that a production deployment
has occurred. Current readiness is BLOCKED; see
[`docs/PHASE_27_COMPLETION_REPORT.md`](../PHASE_27_COMPLETION_REPORT.md).

## 50.1 Prerequisites

- Flutter SDK version recorded by the project: 3.44.8; Dart constraint in
  `pubspec.yaml`: `^3.12.2`. The SDK version was not re-measured in this run.
- Android SDK/NDK and JDK installed for the repository's configured Gradle and
  Android plugin versions. Phase 21 documents Gradle 9.1.0, AGP 9.0.1, Kotlin
  2.3.20, Java bytecode target 17, and Android min/compile/target API 24/36/36;
  confirm these against the installed toolchain before building.
- Node.js/npm and Firebase CLI for local Rules emulator validation and Firebase
  deployment.
- A confirmed production Firebase project, controlled test
  accounts, and an Android test device.
- A protected release/upload keystore. Never place it or its passwords in Git.
- This workspace's `android/local.properties` is machine-local and must be
  created for each developer/CI environment.

## 50.2 Firebase Configuration

Current local configuration points to Firebase project `gendersocialapp` in
`firebase.json`, `.firebaserc`, `google-services.json`, and generated
`lib/core/firebase/firebase_options.dart`. There is no separate development and
production project mapping in the repository. The configured default project
has not been confirmed as the intended production environment; verify this in
Firebase Console before any deployment.

The checked-in generated Firebase options and Android client identifiers are
client configuration, not privileged credentials. `google-services.json` is
ignored by Git; runtime initialization in `AppBootstrap` uses generated Dart
options. Do not add service-account JSON, Admin SDK credentials, private keys, or
server FCM credentials.

Authentication source code uses Firebase email/password create and sign-in.
Provider enablement, email templates, account recovery, authorized domains, and
production account policy must be verified in Firebase Console; this audit could
not inspect the remote project. Source inspection found no password-reset or
account-deletion flow; decide whether those are required for this private
deployment before release.

## 50.3 Android Configuration

- Current namespace/application ID: `com.aj.kam`.
- The local Firebase client file includes registrations for `com.example.kam`
  and `com.aj.kam`; the Gradle ID now matches the latter. This file is ignored
  by Git and must be supplied in each build environment. Changing the ID after
  distribution requires a new Firebase Android registration and installs as a
  distinct Android package.
- Current label: `Know About Me`; launcher artwork is still the Flutter template icon,
  and no production branding asset was identified in the asset directory.
- Current version: `1.0.0+1` (`versionName`/`versionCode` from Flutter values).
- Main manifest permissions: Internet, network state, coarse/fine foreground
  location, and notifications. There is no background location or foreground
  service permission. The Internet permission was added to the main manifest in
  Phase 27 because the prior source declared it only in debug/profile manifests.
- Backup is disabled; full backup and device-transfer rules exclude app-private
  files, databases, and shared preferences.
- Release shrinking/minification is not configured. Do not enable it without a
  release build and install smoke test.
- Release builds use environment-supplied signing and fail before producing
  release APK/AAB artifacts when all signing values are not present. No debug-key
  fallback is configured.

Set these variables securely in the current PowerShell session/CI environment;
do not paste values in source, command logs, or documentation:

```powershell
$env:KAM_RELEASE_STORE_FILE = '<absolute path to protected upload keystore>'
$env:KAM_RELEASE_STORE_PASSWORD = '<provided by secret store>'
$env:KAM_RELEASE_KEY_ALIAS = '<provided by secret store>'
$env:KAM_RELEASE_KEY_PASSWORD = '<provided by secret store>'
```

The placeholders above are instructions only; do not execute them literally.

## 50.4 Build and validation

From the Flutter package directory (`kam/`):

```powershell
flutter pub get
flutter analyze
flutter test
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
flutter build apk --debug
flutter build apk --release
```

The release APK is expected at `build/app/outputs/flutter-apk/app-release.apk`.
The configured distribution method has not been selected, so an AAB is not
assumed. If Google Play is selected, also run `flutter build appbundle --release`
and validate the resulting bundle with the release process.

The release build requires all four signing variables. Record only the artifact
version, checksum, and signing certificate fingerprint in release evidence; do
not record key/password values.

## 50.5 Firebase deployment

The root `firebase.json` targets root `firestore.rules` and
`firestore.indexes.json`. The copies under `firebase/` matched byte-for-byte at
the Phase 27 source audit. Validate locally first:

```powershell
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

The repository currently has `gendersocialapp` as the Firebase CLI default. Do
not rely on that default for production. After a release operator verifies the
intended project and authorization, deploy explicitly:

```powershell
firebase deploy --only firestore:rules --project <confirmed-production-project-id>
firebase deploy --only firestore:indexes --project <confirmed-production-project-id>
```

Replace the placeholder only after confirming the project in Firebase Console.
These deploy commands were not run in Phase 27. Never weaken Rules for rollback
or deployment troubleshooting.

## 50.6 Installation and smoke test

No release artifact was produced in this run. Once built and signed, install on
an authorized test device using:

```powershell
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

On two controlled test accounts/devices, verify launch, authentication, pairing,
mutual consent, sharing gates, partner state, rules, interpretation, notification
delivery and authorized tap, history, pause/resume, revocation, sign-out cleanup,
and offline/reconnect. Also test permission denial and API-specific notification
behavior. A rule match alone does not prove notification delivery. Do not claim
production behavior until these checks actually pass.

## 50.7 Rollback

1. Pause further distribution and record affected artifact version/build number.
2. Reinstall the last known-good APK signed with the same signing key. Android
   does not allow an in-place downgrade to a lower version code; uninstall and
   reinstall may be required and can remove local app data.
3. Keep the prior release artifact and its certificate identity in protected
   release storage. If the signing key is lost, updates under the same package
   may not be possible.
4. Treat Firestore Rules and indexes as independent deployments. Restore the
   prior reviewed Rules file from version control and deploy it only after
   confirming project ID and testing. Never replace them with open access rules.
5. Application rollback does not roll back Firestore data, Rules, or indexes.
   Preserve backward compatibility for schema changes and evaluate data recovery
   separately; no automatic destructive migration is authorized by this runbook.

## 50.8 Known limitations

- Phase 26 is BLOCKED; current automated validation and two-user journeys remain
  unverified.
- Firebase project intent/provider settings are unconfirmed; no deployment was
  performed.
- Release signing secrets and a permanent package identity are not configured.
- No Android device, installed release, selected distribution channel, or prior
  production artifact was available.
- The app uses local notifications; centralized push/FCM delivery and remote
  crash monitoring are not configured.
- Android background collection is best effort; iOS is unsupported.
