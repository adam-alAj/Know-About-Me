# Device State Model (Phase 6)

`DeviceStateSnapshot` is a partial point-in-time local observation with
`deviceId`, `userId`, UTC `collectedAt`, optional UTC `reportedAt`, and a map of
capabilities to `StateObservation` values. Missing map entries are permitted.

Each observation can carry a value, `observedAt`, `updatedAt`, producer/source,
platform, permission state, and a safe error description. Its availability is
explicit: `available`, `unavailable`, `unknown`, `unsupported`,
`permissionDenied`, `error`, or `stale`. Capability registry support is
separate (`supported`, `unsupported`, `permissionRequired`,
`temporarilyUnavailable`, `available`). Permission states are `granted`,
`denied`, `restricted`, `limited`, `notDetermined`, and `notApplicable`.

Serialization uses enum names and ISO-8601 UTC timestamps. The snapshot is a
data contract, not an interpretation. Battery charging does not mean a person
is sleeping; network loss does not mean the phone is powered off. Freshness is
computed from observation timestamps and the shared `FreshnessPolicy`; a stale
reading is never made fresh by serialization.

## Future synchronization payload

The snapshot `toJson()` shape is the Phase 11 starting contract:

```json
{
  "deviceId": "opaque-app-id",
  "userId": "authenticated-owner",
  "collectedAt": "2026-09-26T12:00:00.000Z",
  "reportedAt": null,
  "capabilities": {
    "battery": {
      "availability": "available",
      "value": 72,
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": null,
      "source": "platform-adapter",
      "permissionState": null,
      "platform": "android",
      "error": null
    }
  }
}
```

Do not serialize raw hardware identifiers, credentials, or partner state into a
local device's document. Remote ownership and pair membership must be derived
and enforced by auth plus Security Rules, not trusted from client-supplied IDs.

