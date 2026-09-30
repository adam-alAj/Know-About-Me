# Production Release Checklist

**Current release status: BLOCKED.** This checklist reflects the repository and
environment audit dated 2026-09-30. Do not distribute an artifact until every
release gate below is resolved and evidenced.

## Code and validation

- [ ] Phase 26 integration/acceptance validation completed; it currently reports
  BLOCKED.
- [ ] `flutter pub get` succeeds.
- [ ] `flutter analyze` reports no issues.
- [ ] `flutter test` passes after current source edits.
- [ ] Firestore emulator Rules tests pass against the current root rules and
  indexes.
- [ ] Debug APK build succeeds.
- [ ] Release APK build succeeds with the intended signing key.
- [ ] No release debug bypasses or privileged credentials are present.
- [ ] Release logging remains warning/error only and omits raw exception details.

## Firebase

- [ ] Confirm `gendersocialapp` is the intended production project; the repository
  currently selects it as the default, but project ownership/environment intent
  was not verified.
- [ ] Confirm the production Authentication providers and authorized domains in
  Firebase Console. Client code implements email/password create and sign-in.
- [ ] Confirm the production Firestore database exists and is in the intended
  region.
- [ ] Run current Rules tests before deploying.
- [ ] Confirm required indexes are ready in the intended project.
- [ ] Deploy Rules and indexes only with explicit project selection and an
  authorized operator.
- [ ] Never deploy service-account/Admin credentials or use a broad allow rule.

## Android identity and signing

- [ ] Verify the selected package ID `com.aj.kam` matches the Firebase Android
  client configuration in the build environment. Changing it after distribution
  creates a separate Android app and needs a matching Firebase registration.
- [ ] Verify launcher icon rendering and prepare store metadata. The configured
  display name is `Know About Me`; Android launcher icons use the supplied gold
  emblem in `assets/branding/kam-logo.jpg`.
- [ ] Confirm release version name/code. Current `pubspec.yaml` value is
  `1.0.0+1`; increment the build number for each distributed build.
- [ ] Create/choose a protected upload keystore and store it outside the repo.
- [ ] Supply signing through `KAM_RELEASE_STORE_FILE`,
  `KAM_RELEASE_STORE_PASSWORD`, `KAM_RELEASE_KEY_ALIAS`, and
  `KAM_RELEASE_KEY_PASSWORD` in a secure local environment or CI secret store.
- [ ] Verify the signing certificate fingerprint and keep a protected backup.
- [ ] Ensure the release artifact is not signed with the Android debug key.

## Manifest, privacy, and client behavior

- [ ] Confirm the required permissions in the main manifest: Internet, network
  state, foreground coarse/fine location, and Android 13+ notifications.
- [ ] Confirm no background location or foreground-service permission is added.
- [ ] Validate location denial/reduced accuracy, notification denial, and system
  settings behavior on supported Android versions.
- [ ] Confirm backup/device-transfer exclusions and sign-out cache cleanup.
- [ ] Validate notification content and tap authorization after sign-out, pause,
  sharing disable, and revocation.
- [ ] Decide and implement account recovery/deletion requirements. Current auth
  source has email/password registration and sign-in but no password-reset or
  account-deletion flow.
- [ ] Verify stale/unknown/offline messaging and privacy disclosures.
- [ ] Verify no custom external deep-link entry point bypasses authentication or
  pair authorization.

## Release evidence

- [ ] Install the signed release on a supported Android device.
- [ ] Complete the release smoke journey on a controlled Firebase project.
- [ ] Complete the two-user release journey and cross-pair security checks.
- [ ] Exercise normal network, offline/reconnect, lifecycle, permissions, and
  reinstall/update behavior.
- [ ] Record exact version, signing fingerprint, test environment, and artifact
  checksum in the release record.
- [ ] Archive the previous APK and retain the matching signing key.
- [ ] Confirm distribution channel (private APK or Google Play). No channel is
  selected in this repository audit.
