# ADR-004 — Configuration and environment strategy

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 1

## Context

The app must support development and production environments, must never
hard-code secrets (NFR-029, constraint 5), and must never contain server-side
credentials. It also needs a way to configure feature flags and Firebase
selection without editing code between builds.

## Decision

1. **Compile-time configuration via `--dart-define`**, read once into
   `AppConfig` (`lib/core/config/app_config.dart`):
   - `APP_ENV` → `development` | `staging` | `production` (default
     `development`),
   - `ENABLE_VERBOSE_LOGGING` → bool,
   - `FIREBASE_PROJECT_ID` → public project id (optional in Phase 1).
   Use `--dart-define-from-file=<file>.json` for multi-value local setups.
2. **Inject configuration through a provider**, never read the compiler
   environment inside widgets. `appConfigProvider` is overridden in `main()` and
   in tests.
3. **Only client-safe values may enter `AppConfig`.** A Firebase project id, an
   API base URL and feature flags are client-safe. The following must **never**
   appear in this repository or in the client:
   - Firebase Admin / service-account JSON,
   - private API keys or signing secrets,
   - Cloud Functions secrets,
   - database credentials.
4. **FlutterFire platform config is client configuration, not a secret** — but
   `google-services.json` / `GoogleService-Info.plist` are **not committed in
   Phase 1**, because no Firebase project exists yet (see ADR-002). When created
   in Phase 2, decide explicitly whether they are committed (they are public and
   often are) or injected at build time by CI; the decision is recorded then.
5. See `.gitignore`; Phase 1 adds patterns for `*.env`, `*.env.*`, and
   service-account key files as defence in depth.

## Consequences

Positive:

- No secret-handling path exists in the client at all.
- The same binary configuration mechanism works for local dev, CI and stores.
- Tests get deterministic configuration through a provider override.

Negative / accepted trade-offs:

- Changing configuration requires a rebuild (no runtime config service). This is
  acceptable at this stage; a remote-config solution can be added later behind
  the same `AppConfig` interface.
- `String.fromEnvironment` values are `const`, so they cannot be changed after
  compilation — intentional.

## Alternatives considered

- **`.env` files loaded at runtime with `flutter_dotenv`.** Rejected: an `.env`
  file bundled as an asset is still shipped in the binary, which invites putting
  secrets there and gives false security.
- **Hard-coding environment constants.** Rejected: violates NFR-029 and makes
  production builds error-prone.
- **A backend config endpoint.** Deferred: adds a network dependency to startup
  before there is a backend.
