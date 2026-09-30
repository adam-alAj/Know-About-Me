# Troubleshooting and Maintenance

Commands are intended for the `kam/` package root. Never include passwords,
tokens, exact location, or private user records in logs or support requests.

## Authentication and profiles

- **Sign-in/registration fails:** check device connectivity, Firebase Auth
  provider configuration in the selected project, app config/project ID, and
  the safe mapped message. Do not expose credentials or raw Firebase exceptions.
- **Session appears expired:** sign in again. A sign-out/session-loss path clears
  protected local observations; it intentionally retains the opaque local device
  ID and sync version.
- **Profile unavailable:** check Firestore availability and authenticated
  ownership. A successful Auth session alone does not authorize arbitrary
  Firestore paths.
- **Password reset/account deletion:** no app flow was found for these features;
  this is a product/release limitation, not a recoverable screen error.

## Pairing, consent and connection state

- **Code rejected:** verify exact code, expiry, issuer is another user, and that
  the code has not been consumed/revoked. Generate a fresh code rather than
  retrying a stale one.
- **Pair remains pending:** both users must complete their own consent. A code
  redemption is not activation.
- **Pair paused/revoked:** inspect the pair lifecycle and each owner's sharing
  state. Do not edit Firestore directly to “repair” consent or membership.
- **Permission denied:** distinguish Firebase Rules authorization from Android
  OS permission. Firebase `permission-denied` is not evidence of location
  permission denial.

## Device state, location and stale observations

- **Unknown/unavailable value:** inspect capability support, Android permission,
  sensor/API result and observation timestamp. Preserve unknown/error; do not
  substitute `false`.
- **Stale value:** Android may delay collection in background. Resume the app and
  allow a new observation/sync; show the old observation time until then.
- **Location missing:** check location services, coarse/fine permission and app
  sharing separately. Collection is foreground-only. Reduced accuracy and
  temporary unavailability are valid states.
- **No network/partner unreachable:** show offline/last-seen semantics, not
  powered off. Network path does not prove Firebase reachability.
- **Activity/display discrepancy:** Android/OEM lifecycle and receiver delivery
  may omit transitions; screen off does not mean sleeping.

## Firebase and Firestore

- **App unexpectedly uses a real project:** `AppBootstrap.run()` enables
  generated Firebase options. Confirm compile-time project defines and
  `FIREBASE_USE_EMULATORS`; `APP_ENV` does not select a Firebase project.
- **Emulator connection refused:** start the emulator on Firestore 8080/Auth 9099;
  set `FIREBASE_EMULATOR_HOST` to `localhost` for desktop, `10.0.2.2` for
  Android Emulator, or a reachable LAN host for a physical device.
- **Rules test could reach wrong project:** run with explicit
  `--project demo-kam`. Never use the repository's `gendersocialapp` CLI default
  for emulator testing.
- **`permission-denied`:** verify current auth UID, pair membership/status,
  mutual consent, not-paused state, owner category sharing, ownership/path, and
  field schema. Do not weaken Security Rules.
- **Missing composite index / failed precondition:** compare query with root
  `firestore.indexes.json`; test Rules/indexes in emulator and deploy only after
  confirming project ID. Use the project-specific console link only from trusted
  Firebase tooling.
- **Configuration mismatch:** required alternate client values are project ID,
  API key, app ID, and sender ID together. Partial Dart defines fail closed.

## Notifications

- **Rule matched, no alert:** a match is only eligibility. Check freshness,
  preference/cooldown, Android 13+ notification permission, channel and app
  settings. The implementation is local Android notification, not remote FCM.
- **Channel disabled:** enable the `Rule alerts` channel in Android app settings.
- **Tap behavior:** rule ID is a launch extra; authorization/tap recovery has not
  been validated on a device. Do not infer access from a notification payload.

## Android, ADB and build

- **ADB reports `.android` permission denied:** verify the Windows user-profile
  Android directory is writable and `ANDROID_USER_HOME` points to a writable
  directory. Re-run `adb devices -l`. This workaround was not validated in the
  current workspace.
- **Release task says signing is not configured:** set all four `KAM_RELEASE_*`
  variables from an authorized secure source. Do not use the Android debug key
  or print values while diagnosing.
- **Release app cannot access network:** confirm the main manifest includes
  `android.permission.INTERNET` and inspect the merged manifest/build output.
- **Release artifact does not install over an old one:** package ID and signing
  certificate must match; downgrading version code can require uninstall and
  may remove app-local data.

## Testing and validation environment

In the recorded workspace Flutter commands stalled without output, Firebase CLI
and Node/npm were absent, and ADB could not initialize its user directory. If
that recurs, record the command, wait duration and exact output as BLOCKED; do
not count it as a pass. Historical 617/617 Flutter and 114/114 Rules results are
Phase 19 only.

## Operational maintenance

Review these areas before each release or material dependency update:

- Firestore Security Rules, index definitions and mirror parity.
- Firebase project selection, Android registration, Auth providers and account
  configuration.
- Android permissions, API targets, notification channel, backup rules and
  lifecycle behavior.
- Flutter/Dart, Gradle/AGP/Kotlin/JDK, Android SDK and Firebase SDK compatibility.
- Firestore schema, bounded local-cache schema and sensitive-data cleanup.
- Rule freshness/evaluation semantics, notification eligibility and duplicate
  behavior.
- Release signing key custody, version code, package identity, artifact checksum
  and previous artifact retention.
- Spark plan compatibility, Firestore reads/writes/listeners and documented
  operational limitations; no live performance/usage metrics were collected.

