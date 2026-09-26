abstract interface class NetworkPlatformGateway {
  String get platformName;
  Future<Object?> readCurrent();
  Stream<Object?> watchChanges();
}

/// Untrusted raw response from a platform adapter. Domain normalization and
/// validation happen in [NetworkStateCollector].
class NetworkPlatformSample {
  const NetworkPlatformSample({
    required this.connectivityType,
    required this.internetReachability,
    required this.onlineStatus,
  });

  final String? connectivityType;
  final String? internetReachability;
  final String? onlineStatus;

  factory NetworkPlatformSample.fromPlatform(Object? value) {
    if (value is NetworkPlatformSample) return value;
    if (value is! Map) {
      throw const FormatException('Native network response was not a map.');
    }
    return NetworkPlatformSample(
      connectivityType: value['connectivityType'] as String?,
      internetReachability: value['internetReachability'] as String?,
      onlineStatus: value['onlineStatus'] as String?,
    );
  }
}
