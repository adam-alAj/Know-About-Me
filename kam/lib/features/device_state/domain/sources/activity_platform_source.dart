/// Platform-neutral activity source. Tests inject a fake instead of invoking
/// native channels.
///
/// The gateway carries only the display-state signal; this application's own
/// lifecycle arrives through the Flutter framework and never crosses this
/// boundary.
abstract interface class ActivityPlatformGateway {
  Future<Object?> readCurrent();
  Stream<Object?> watchChanges();
  String get platformName;
}

/// Raw platform response. Unknown or missing values stay intact so the
/// collector can report them as `unknown`/`unavailable` instead of inventing
/// a display state.
class ActivityPlatformSample {
  const ActivityPlatformSample({
    required this.screenStateSupported,
    this.screenState,
  });

  /// Whether the platform claims a display-state capability at all.
  final bool screenStateSupported;

  /// Raw value: `on`, `off`, `unknown`, or `null` when the platform returned
  /// nothing.
  final String? screenState;

  factory ActivityPlatformSample.fromPlatform(Object? value) {
    // Test and in-process adapters may already return the normalized sample.
    if (value is ActivityPlatformSample) return value;
    if (value is! Map) {
      throw const FormatException('Native activity response was not a map.');
    }
    return ActivityPlatformSample(
      screenStateSupported: value['screenStateSupported'] == true,
      screenState: value['screenState'] as String?,
    );
  }
}
