# ADR-002 — Firebase responsibility boundaries and deferred integration

- **Status:** Accepted
- **Date:** 2026-09-26
- **Phase:** 1

## Context

The SRS names Firebase as the expected backend (`Firebase Auth`,
`Cloud Firestore`, `Firebase Cloud Messaging`, Cloud Functions) and requires
that access control be enforced server-side, not merely in the Flutter client
(FR-063), that one pair's data never be visible to another (FR-064), and that
secrets never ship in the client (NFR-029, constraint 5).

Phase 1 has **no Firebase project and no platform configuration files**
(`google-services.json`, `GoogleService-Info.plist`). Adding the FlutterFire
packages now would either fail the build or produce an integration that compiles
but cannot run.

## Decision

1. **Do not add Firebase packages in Phase 1.** The application builds and runs
   fully offline with placeholder data.
2. Provide a documented boundary, `lib/core/firebase/firebase_bootstrap.dart`,
   whose `initialize` returns `false` until Phase 2 wires the real SDK.
3. Fix the **responsibility split** now, so later phases do not redesign it:

   | Concern | Owner |
   | --- | --- |
   | User identity | Firebase Auth (client collects credentials, Auth issues identity) |
   | Pairing code generation/validation | **Cloud Functions** — must be unguessable, expiring and single-use; cannot be client-trusted |
   | Consent and its enforcement | Firestore, validated by Security Rules |
   | Pair isolation / revocation | **Firestore Security Rules** (FR-063, FR-064, FR-065) |
   | Device state (current) | Client writes, Firestore stores, only for currently shared categories |
   | Meaningful events | Client writes, Firestore stores (no raw high-frequency telemetry, NFR-039) |
   | Rule definitions | Firestore, owned by a user |
   | Rule evaluation | Client for the initial scope; Cloud Functions where a result must be trusted by the other user or must fire a push |
   | Push notifications | FCM, typically triggered server-side |
   | Secrets (Admin SDK, private API keys, Functions secrets) | **Server only — never in the client** |

4. The general rule: **authorization is enforced server-side; observation happens
   client-side.** A client may *describe* its own device; it may never be the
   authority on who is allowed to read another person's data.

## Consequences

Positive:

- Phase 1 has a clean, buildable project with no half-configured backend.
- The client/server trust boundary is decided before code depends on it.
- `FirebaseBootstrap.isInitialized` already exists as the switch Phase 2 flips.

Negative / accepted trade-offs:

- Phase 2 must add dependencies, platform config and initialization; this is a
  known, planned cost rather than a hidden one.
- Until Phase 2, no feature can be demonstrated end-to-end across two devices.

## Alternatives considered

- **Add `firebase_core` now with a placeholder `google-services.json`.** Rejected:
  it would build but fail at runtime, and committing a fake project config is
  misleading and easy to mistake for real setup.
- **Add Firebase packages without initialization.** Rejected: unused native
  plugins increase build surface and dependency risk for no Phase 1 benefit.
- **Client-side-only authorization for now.** Rejected outright: it contradicts
  FR-063 and would require redesign later.
