# Device State Model (Phases 6–10)

`DeviceStateSnapshot` is a partial point-in-time local observation with
`deviceId`, `userId`, UTC `collectedAt`, optional UTC `reportedAt`, and a map of
capabilities to `StateObservation` values. Missing map entries are permitted.
Its optional typed `battery` value contains separate percentage, charging,
duration, and source observations plus a charging start timestamp when that
start was observed. Its optional typed `network` value separates connectivity
transport, Internet reachability, online status, last observed online time,
and an offline duration that exists only after an observed transition. Its
optional typed `location` value (Phase 10) carries one `LocationFix` as the
current read or as explicitly stale, the same fix as labelled history, the
normalized permission and OS service state, the derived distance from home, the
at-home/away/unknown presence, and home configuration facts (configured,
enabled, radius) — never the home coordinates themselves.

Each observation can carry a value, `observedAt`, `updatedAt`, producer/source,
platform, permission state, and a safe error description. Its availability is
explicit: `available`, `unavailable`, `unknown`, `unsupported`,
`permissionDenied`, `serviceDisabled` (Phase 10: permission granted but the OS
service is off), `error`, or `stale`. Capability registry support is
separate (`supported`, `unsupported`, `permissionRequired`,
`temporarilyUnavailable`, `available`). Permission states are `granted`,
`denied`, `permanentlyDenied`, `restricted`, `limited`, `notDetermined`,
`unknown`, and `notApplicable`. Location fixes additionally carry the
platform's own `accuracyMeters` and an `approximate` flag so a reduced-accuracy
grant is never presented as a precise position.

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
  "location": {
    "location": {
      "availability": "available",
      "value": {
        "latitude": 31.9038,
        "longitude": 35.2034,
        "observedAt": "2026-09-26T12:00:00.000Z",
        "accuracyMeters": 18.0,
        "approximate": false,
        "source": "android.location_manager"
      },
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android.location_manager",
      "permissionState": "granted",
      "platform": "android",
      "error": null
    },
    "lastKnownLocation": {
      "availability": "stale",
      "value": {
        "latitude": 31.9038,
        "longitude": 35.2034,
        "observedAt": "2026-09-26T09:15:00.000Z",
        "accuracyMeters": 32.0,
        "approximate": false,
        "source": "android.location_manager"
      },
      "observedAt": "2026-09-26T09:15:00.000Z",
      "updatedAt": "2026-09-26T09:15:00.000Z",
      "source": "android.location_manager",
      "permissionState": "granted",
      "platform": "android",
      "error": null
    },
    "permission": {
      "availability": "available",
      "value": "granted",
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": "android.location_manager",
      "permissionState": "granted",
      "platform": "android",
      "error": null
    },
    "serviceState": "enabled",
    "distanceFromHome": {
      "availability": "available",
      "value": 740.0,
      "observedAt": "2026-09-26T12:00:00.000Z",
      "updatedAt": "2026-09-26T12:00:00.000Z",
      "source": null,
      "permissionState": null,
      "platform": null,
      "error": null
    },
    "presence": "awayFromHome",
    "homeConfigured": true,
    "homeEnabled": true,
    "homeRadiusMeters": 300.0
  },
  "capabilities": {}
}
```

The `location.value` above is fresh while the retained history is stale, so the
two never share an age. `presence` is derived: it is `unknown` whenever the fix
or the home is unusable, and `awayFromHome` only from a usable fix beyond the
radius.

Do not serialize raw hardware identifiers, credentials, or partner state into a
local device's document. Remote ownership and pair membership must be derived
and enforced by auth plus Security Rules, not trusted from client-supplied IDs.
