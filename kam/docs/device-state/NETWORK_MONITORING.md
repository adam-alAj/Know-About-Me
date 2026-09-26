# Network Connectivity and Online/Offline Monitoring (Phase 8)

## Normalized observations

`NetworkState` contains independent observations for:

- `connectivity`: selected transport (`wifi`, `mobile`, `ethernet`,
  `bluetooth`, `vpn`, `none`, or `unknown`);
- `internet`: platform evidence for general Internet reachability;
- `status`: `online`, `offline`, or `unknown` according to the OS network path;
- `lastOnlineAt`: most recent timestamp at which this app observed online;
- `offlineStartedAt` and `offlineDuration`: only populated when an online to
  offline transition was observed during the current monitoring session.

Every observation has an availability and timestamp. Its freshness is
classified using the shared standard policy. Stale means the last reading is
old; it does not mean the device is currently offline.

`online` means the OS currently reports a usable network path. On Android,
online requires `NET_CAPABILITY_VALIDATED`, which is system evidence that
Internet access was detected. A path with no validation is offline from this
app's general-Internet perspective, even if Wi-Fi transport is present. On iOS,
`NWPath.Status.satisfied` means a network connection attempt can be made; it
does not establish general Internet or Firebase availability, so
`internetReachability` stays unknown while status can be online. Neither status
means the phone is powered on continuously, that Firebase is reachable, or that
the person is using the phone.

## Transitions, last online, and duration

The collector updates `lastOnlineAt` when it observes an online state after a
non-online baseline. Repeated online readings do not rewrite it. The UTC value
is persisted in app-private preferences so historical last-online time remains
available across restart. It is informational, not a trusted clock or security
input. Invalid/future persisted timestamps are ignored.

`offlineDuration` is available only when this process observes online followed
by offline and continues receiving observations. It is measured with a
monotonic stopwatch. First observation offline, app restart, lifecycle stop,
network error, or unknown status leaves duration unknown because the actual
offline start may have preceded the observation gap. It is not inferred from
the age of the last-online timestamp. No offline history is persisted.

The app refreshes on demand and observes OS network events while monitoring is
active. Resume starts collection again and refreshes current state. The OS can
suspend or terminate the app; missed events are not reconstructed and there is
no 24/7 monitoring promise. A missing update is stale/unknown evidence, not
proof of offline or powered-off state.

## Platform behavior

### Android

Uses `ConnectivityManager` and a default-network callback. `ACCESS_NETWORK_STATE`
is required; no Wi-Fi identifiers, addresses, or credentials are collected.
Transport is normalized from `NetworkCapabilities`. A VPN is reported as VPN
when it is the selected default transport. `NET_CAPABILITY_VALIDATED` informs
the Internet observation. On older Android releases, the callback fallback
observes Internet-capable networks with reduced default-network precision.

### iOS

Uses `NWPathMonitor`, requiring no user permission or Info.plist entry. Wi-Fi,
cellular, and wired Ethernet are recognized; other usable interfaces remain
unknown. The API has no direct general-Internet validation signal, and the app
does not probe a third-party endpoint. Thus Internet and Firebase reachability
are not inferred from `NWPath`.

Sources: [Android ConnectivityManager](https://developer.android.com/reference/android/net/ConnectivityManager),
[Android reading network state](https://developer.android.com/develop/connectivity/network-ops/reading-network-state),
[Android NetworkCapabilities](https://developer.android.com/reference/android/net/NetworkCapabilities),
[Apple NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor),
[Apple NWPath](https://developer.apple.com/documentation/network/nwpath).

## Boundaries and privacy

The collector is local and independent of authentication, pairing, battery
collection, and Firebase requests. A Firebase failure is never used as a
connectivity signal. The local snapshot's network value is not partner state;
Phase 11 owns authorized synchronization and remote freshness. No heartbeat,
Firestore writes, IP/SSID/BSSID collection, behavior inference, or power-off
detection is implemented.
