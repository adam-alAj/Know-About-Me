/// Categories of information a user can independently share or hide
/// (SRS FR-021, FR-052, NFR-002).
///
/// Category-level granularity is required so that pausing location does not
/// force the user to disconnect the whole relationship (FR-021).
enum SharingCategory {
  battery,
  charging,
  network,
  location,
  distanceFromHome,
  activityIndicators,
  ruleInterpretations,
}
