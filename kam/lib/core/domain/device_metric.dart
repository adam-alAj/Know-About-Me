/// Canonical identity of a device metric that can be **observed**.
///
/// This is deliberately distinct from `RuleMetric` (which lives in the rules
/// feature and lists everything a rule may *evaluate*, including values that are
/// derived rather than measured). [DeviceMetric] answers "what can a platform
/// collector actually produce?", which is what capability reporting needs.
///
/// Keeping this in `core/` lets the platform abstraction, the capability
/// report and the rules feature all agree on one vocabulary without any of them
/// depending on each other.
enum DeviceMetric {
  batteryPercentage,
  chargingState,
  chargingDuration,
  networkStatus,
  networkConnectivity,
  internetReachability,
  deviceAvailability,
  offlineDuration,
  lastActivity,
  activityState,
  location,
  preciseLocation,
  approximateLocation,
  backgroundLocation,
  homeLocation,
  distanceFromHome,
  homePresence,
  screenState,
  appLifecycle,
  backgroundMonitoring,
  chargingSource,
}
