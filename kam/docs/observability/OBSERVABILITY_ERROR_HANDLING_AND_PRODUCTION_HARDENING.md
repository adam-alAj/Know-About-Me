# Observability, Error Handling and Production Hardening

## 43.1 Error Architecture

The app uses `Result<T>` for repository operations, `AppFailure` for safe presentation, and `AppException` for typed lower-level failures. `FirebaseErrorMapper` maps Firebase Auth and Firestore codes into the existing failure vocabulary. Phase 25 adds `AuthorizationFailure` (server-side rule denial, distinct from OS `PermissionFailure`) and `LocalStorageFailure`. Other existing categories cover authentication, configuration, remote service, validation, not-found, unsupported capability, and unexpected failures. Failure objects can retain a cause for controlled diagnostics; user-facing widgets render only the safe `message`.

Firebase `permission-denied` maps to an authorization message; `unauthenticated` maps to an expired-session message; invalid arguments and failed preconditions map to validation; service availability, deadline, resource exhaustion, aborted/cancelled and unknown service codes remain remote failures. Auth credential messages remain intentionally vague to avoid account enumeration. Raw SDK messages are not shown in UI.

Expected platform limitations are represented in capability/state models (unsupported, permission-required/denied, unavailable, error) rather than fabricated values. Unknown/error/stale remain distinct from false/current. Repository failures propagate as results or stream errors; best-effort event recording is logged by operation and failure type. History clear returns a `Result` and the screen presents a safe error if either local or remote deletion fails.

## 43.2 Firebase Error Handling

The existing mapper handles `permission-denied`, `unauthenticated`, `not-found`, `unavailable`, `network-request-failed`, `retry-limit-exceeded`, `deadline-exceeded`, `resource-exhausted`, `failed-precondition`, `cancelled`, `already-exists`, `invalid-argument`, `unimplemented`, `internal`, and `unknown`; unrecognized Firebase failures remain a generic remote-service failure. Auth has separate mappings for invalid credentials, account states, validation, rate limits, and configuration errors.

Device synchronization retains its existing four-attempt, exponential retry budget. It classifies permission/unauthenticated as blocked and does not retry them; invalid/precondition errors are rejected. Other failures use the bounded retry policy. Pairing/auth/profile operations are user-triggered and are not automatically retried by a new Phase 25 loop. Firestore Rules continue to evaluate each queued SDK write when it reaches the service. No queued operation gains a bypass or alternate path.

History event creation uses deterministic document IDs and create-only rules. `permission-denied` is no longer silently assumed to mean “duplicate”: the repository propagates it to the recorder for safe classification/logging. The local copy is retained. The precise cause can remain ambiguous because Firestore reports both create-only duplicate attempts and revoked authorization as permission-denied.

## 43.3 Authentication Failures

The auth stream remains the single identity source. Stream exceptions now pass through `FirebaseErrorMapper` before the controller enters `AuthError`; an outage is not represented as signed out. The existing router sends `AuthError` to the splash/retry route and denies protected routes until auth is known. Session loss invalidates auth-keyed profile/preferences and invokes the existing `SensitiveLocalData` cleanup. Explicit sign-out uses the same cleanup mechanism. Cleanup is best-effort so it cannot prevent signing out, but failure is now logged without identifiers or raw exception detail in release.

## 43.4 Offline / Recovery

Phase 20's implementation remains authoritative: Firestore SDK owns its pending write queue; the device state service owns only its existing in-memory latest-snapshot coalescer and bounded retry. It is not a durable generic operation queue. Pair/auth/sharing state providers continue to constrain sync scope; Rules are the final authorization boundary. Permission failures are blocked instead of blindly retried. No parallel offline subsystem was added.

## 43.5 Android Errors

Battery, network, activity, and location collectors keep their capability observations and distinguish unsupported, denied, unavailable, and error states. Native location exceptions do not become coordinates. OS permissions remain separate from partner sharing. The manifest requests notification, network-state, and foreground coarse/fine location only; no background location or foreground service is declared. Android APIs were source-audited; device failure-injection was unavailable.

## 43.6 Logging

`AppLogger` remains the only application logging boundary; `DeveloperAppLogger` writes to `dart:developer`, and `NoopAppLogger` remains available to tests. Levels are debug, info, warning, and error. Development/staging may use verbose diagnostics. Release builds default `APP_ENV` to production, cannot enable verbose logging through `ENABLE_VERBOSE_LOGGING`, use warning as the minimum level, and omit raw exception messages and stack traces. Error type remains available for local diagnosis.

The logger redacts sensitive context keys after normalizing punctuation/case, including password/token/API key/email/location/coordinates/UID/pair/device/document path. Map and iterable context values are omitted so a caller cannot accidentally log a full document. Call sites use fixed messages and selected scalar context; there is no remote telemetry sink. Debug details may still appear in local debug tooling and must not be shared as production logs.

`AppErrorBoundary` retains its safe widget fallback and now registers `FlutterError.onError` and `PlatformDispatcher.onError`. Both record through the configured logger; the async dispatcher marks the error handled after logging. Production logging suppresses raw error and stack data. This is a local error boundary, not a crash-reporting service.

## 43.7 Security

No Firestore rules, auth credentials, pairing authorization, sharing checks, or pair scopes were changed. `AuthorizationFailure` only improves classification and user feedback; it does not grant access. Sign-out cleanup remains centralized in `SensitiveLocalData`. The repository scan found the ignored `android/app/google-services.json` client configuration file, which is not a privileged service credential; the architecture test scans for service-account/private-key markers. No signing key or `key.properties` is present. Release signing no longer falls back to the Android debug key.

Production release artifacts now require a protected signing configuration supplied by the release pipeline. The repository has no production signing setup, so a distributable signed release is not ready. Firebase client identifiers are not server credentials. The local Firebase project config is not a service-account file.

## 43.8 Production Hardening

- **Startup:** Firebase initialization failures already degrade to an unavailable/offline service. Unexpected bootstrap exceptions now log safely and show a retryable startup fallback instead of leaving the app before `runApp`.
- **Lifecycle/navigation:** existing auth and pair guards remain; protected routes require resolved auth and app providers remain scope-aware. Local notification payloads do not create a route or bypass the current router guard.
- **Notifications:** local permission/API failures return classified `Result` values; unsupported delivery remains explicit. No remote FCM sender exists and no delivery claim was added.
- **Android release:** exported launcher activity is the only declared activity, backup is disabled and backup/extraction XML excludes app data, cleartext traffic is not enabled in the manifest, and no background location/service permission was found. SDK targets were not changed. Release signing must be configured outside source control.
- **Firebase configuration:** an emulator request in a production or release build is rejected and Firebase stays unavailable, preventing accidental emulator routing in a release artifact.

## 43.9 Testing

Actual Phase 25 commands and results are recorded in [Phase 25 completion report](../PHASE_25_COMPLETION_REPORT.md). Dart formatting and `git diff --check` completed. Flutter dependency resolution, analyze, tests, and APK build stalled without output; Firebase emulator command failed because the Firebase CLI and npm are absent. No result is reported as passed unless it completed.

## 43.10 Known Limitations

- Flutter/Dart commands stalled in this environment, preventing compilation and regression validation of the changes.
- Firebase CLI/npm, a working Android device/emulator, and two independent user accounts were unavailable.
- No Android Logcat, emulator authorization-denial, offline replay, storage corruption, startup failure, or notification tap after revoke test ran.
- Production signing configuration is intentionally not provided; signed release delivery remains blocked.
- Android `applicationId` and namespace are `com.aj.kam`; confirm the matching local Firebase client registration is present in every release build environment.
- There is no remote observability/crash reporting, consistent with Spark-only constraints.
- The Phase 25 checkout does not contain the original SRS document; `docs/requirements/REQUIREMENT_MAPPING.md` and the Phase reports were inspected instead.
- Firebase cannot distinguish a duplicate create-only history event write from another permission denial using only the error code. The error is surfaced to local diagnostics and never used to bypass rules.
