# Spark-only architecture: remove Cloud Functions

> Migration decision requested by the Spark-only brief. The canonical numbered
> decision is [ADR-009](ADR-009-spark-only-no-cloud-functions.md), because
> ADR-004 is already assigned to configuration strategy. This file preserves
> the requested artifact path and summarizes the same accepted decision.

## Context

The project must work on Firebase Spark without a billing account. Cloud
Functions require the Blaze plan, even when usage would otherwise be within a
no-cost allowance. No Functions source or Admin SDK dependency existed; the
previous architecture only planned Functions for pair activation, pairing-code
issuance, notifications, rule evaluation, and scheduled cleanup.

## Decision

Use a Spark-compatible architecture with Flutter, Firebase Authentication,
Cloud Firestore, Firestore Security Rules, client-side domain logic, and local
notifications. Do not deploy Cloud Functions, Cloud Run, Cloud Scheduler,
Pub/Sub, or a Firebase Extension that requires them. Firestore Rules remain the
authorization authority. The unused Functions emulator configuration was
removed.

## Consequences

- Rule evaluation and notification planning run in Flutter while the app process
  is available. The local notification service is an abstraction; its current
  implementation reports unsupported until a platform plugin is connected.
- Firestore Rules verify ownership, pair membership and isolation, sharing
  consent, code redemption, and owner-scoped notification records.
- Authentication uses the Firebase client SDK. FCM has no server-side sending
  path; remote push to a partner is deferred.
- Cross-user scheduled retention and server-authoritative rate limiting are
  deferred. Clients can only perform ownership-scoped cleanup.
- Background execution is controlled by Android and iOS. When the app is not
  running, the rule engine cannot promise continuous evaluation; the product
  must show last-known state, its timestamp, and stale or unknown status.
- Firebase services in use are Authentication and Cloud Firestore. Local
  development uses the Auth and Firestore Emulator Suite. FCM registration is
  not currently wired into the application.

## Security implications

No Admin credential, FCM sending credential, private API key, or other server
secret may be put in Flutter, `.env`, Remote Config, assets, native
configuration, or obfuscated code. A trusted server operation that cannot be
enforced by Firestore Rules must remain deferred; client-side checks are never
a substitute for authorization. See [Spark-only architecture](../architecture/SPARK_ONLY_ARCHITECTURE.md)
and the [migration completion report](../SPARK_MIGRATION_COMPLETION_REPORT.md)
for the operation inventory, rule design, validation, and limitations.
