# Developer Setup

Run commands from the Flutter package root (`kam/`). This guide is written for a
clean Windows developer machine; adjust shell/path details on other hosts.

## Prerequisites

| Tool | Repository requirement/status |
| --- | --- |
| Git | Clone/read the repository. |
| Flutter | Repository docs record Flutter 3.44.8; verify the installed SDK with `flutter --version`. |
| Dart | `pubspec.yaml` requires Dart `^3.12.2`; Flutter supplies Dart. |
| Java | Android build bytecode target is 17. Use a JDK compatible with the Android Gradle Plugin; Phase 21 records target 17, not a successful current build. |
| Android SDK | Android min/compile/target SDK values are recorded as 24/36/36. Install the required platform/build tools and accept licenses. |
| Android device/emulator | Required for Android runtime and permission/lifecycle validation. Current workspace ADB initialization was blocked. |
| Node.js/npm | Required only for Firestore Rules tests under `firebase/`; versions are not pinned as a project prerequisite. |
| Firebase CLI | Required for local Firebase emulators and Firebase deployment. Do not deploy without confirming project ID. |

Use `flutter doctor -v` and `flutter --version` to inspect a new installation.
Current execution environment did not complete Flutter commands, so listed
repository tool versions are not a successful build certification.

## Clone and install Flutter dependencies

```powershell
git clone <repository-url>
Set-Location <repository-directory>\kam
flutter pub get
```

No private package registry or committed `.env` file is required. Flutter creates
machine-local Android configuration such as `android/local.properties`; keep it
out of version control.

## Firebase setup and safe local development

The app currently loads generated options for `gendersocialapp` on normal
bootstrap, including development unless a full alternate configuration is
provided. `APP_ENV=development` changes environment/logging policy only; it does
not redirect Firebase. Before using default `flutter run`, confirm the selected
Firebase project is safe for your data.

For isolated app development, install Node/npm and Firebase CLI, then start the
local Authentication and Firestore emulators using the demo-only project:

```powershell
firebase emulators:start --project demo-kam --only firestore,auth
```

In a second terminal, run the Android app with complete dummy client options and
an Android Emulator host address:

```powershell
flutter run `
  --dart-define=APP_ENV=development `
  --dart-define=FIREBASE_PROJECT_ID=demo-kam `
  --dart-define=FIREBASE_API_KEY=demo-api-key `
  --dart-define=FIREBASE_APP_ID=1:000000000000:android:0000000000000000000000 `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=000000000000 `
  --dart-define=FIREBASE_USE_EMULATORS=true `
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

For a desktop target use `localhost`; for a physical Android device use a
development host IP reachable on the same network. The emulator adapter uses
Firestore port 8080 and Auth port 9099. There is no FCM emulator or FCM client in
the app.

If compile-time Firebase identifiers are supplied, provide all four required
values: project ID, API key, app ID, and messaging sender ID. Partial
configuration fails closed. Never put server credentials in Dart defines.

## Run the app

```powershell
flutter pub get
flutter run
```

The default command may target the configured `gendersocialapp` project. There
is no general normal-run switch that disables generated Firebase options; use
the emulator configuration above for isolated development.

## Run tests and analyzer

```powershell
flutter analyze
flutter test
firebase emulators:exec --project demo-kam --only firestore "npm --prefix firebase test"
```

The emulator test project is explicitly `demo-kam`; do not omit `--project`,
because `.firebaserc` currently defaults to `gendersocialapp`. The JavaScript
test script is `npm --prefix firebase test` and test dependencies are declared
in `firebase/package.json`/lockfile.

## Android debug build

```powershell
flutter build apk --debug
```

Expected output: `build/app/outputs/flutter-apk/app-debug.apk`. An APK build does
not validate runtime permissions, Firebase project choice, or two-user behavior.

## Release build

Current release signing is supplied through secure environment variables. The
release task graph refuses APK/AAB artifact tasks unless all four are present:

- `KAM_RELEASE_STORE_FILE`
- `KAM_RELEASE_STORE_PASSWORD`
- `KAM_RELEASE_KEY_ALIAS`
- `KAM_RELEASE_KEY_PASSWORD`

Get values from an authorized secret store; do not echo them, commit them, or
paste them into issue logs. Then run:

```powershell
flutter build apk --release
```

Expected APK output: `build/app/outputs/flutter-apk/app-release.apk`. If the
approved distribution channel requires Android App Bundle, first confirm that
choice, then run `flutter build appbundle --release`. No signing secrets,
keystore, or artifact are currently available in this checkout.

## Verify the environment

```powershell
flutter --version
flutter doctor -v
java -version
adb devices -l
node --version
npm --version
firebase --version
```

`node`, npm, and Firebase CLI are needed only for emulator/Rules/deployment
tasks. A physical device/emulator is required for Android runtime checks. Keep
their actual outputs with the test/release record; do not replace missing outputs
with the historical Phase 19 counts.
