# Device State Model (Phases 6–8)

`DeviceStateSnapshot` is a partial point-in-time local observation with
`deviceId`, `userId`, UTC `collectedAt`, optional UTC `reportedAt`, and a map of
capabilities to `StateObservation` values. Missing map entries are permitted.
Its optional typed `battery` value contains separate percentage, charging,
duration, and source observations plus a charging start timestamp when that
start was observed. Its optional typed `network` value separates connectivity
transport, Internet reachability, online status, last observed online time,
and an offline duration that exists only after an observed transition.

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
  "battery": {
    "percentage": {
      "availability": "available",
      "value": 72,
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "chargingState": {
      "availability": "available",
      "value": "discharging",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "chargingDuration": {
      "availability": "unavailable",
      "value": null,
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": null,
      "source": "observed_transition",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "chargingSource": {
      "availability": "available",
      "value": "unknown",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": null,
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "chargingStartedAt": null
  },
  "network": {
    "connectivity": {
      "availability": "available",
      "value": "wifi",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "internet": {
      "availability": "available",
      "value": "available",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "status": {
      "availability": "available",
      "value": "online",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android",
      "permissionState": null,
      "platform": "android",
      "error": null
    },
    "lastOnlineAt": "2026-09-26T12:00:00.000Z",
    "offlineStartedAt": null,
    "offlineDuration": {
      "availability": "unavailable",
      "value": null,
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": null,
      "source": "observed_transition",
      "permissionState": null,
      "platform": "android",
      "error": null
    }
  },
  "capabilities": {
    "location": { "availability": "unsupported", "value": null }
  }
}
```

Do not serialize raw hardware identifiers, credentials, or partner state into a
local device's document. Remote ownership and pair membership must be derived
and enforced by auth plus Security Rules, not trusted from client-supplied IDs.
