import '../../../../core/freshness/data_freshness.dart';
import 'state_observation.dart';

enum ConnectivityType { wifi, mobile, ethernet, bluetooth, vpn, none, unknown }

/// Whether the operating system has evidence for general Internet access.
/// This is separate from the selected network transport.
enum InternetReachability { available, unavailable, unknown }

/// `online` means the OS currently reports a usable network path. It says
/// nothing about device power, Firebase availability, or human activity.
enum NetworkOnlineStatus { online, offline, unknown }

class NetworkState {
  const NetworkState({
    required this.connectivity,
    required this.internet,
    required this.status,
    required this.offlineDuration,
    this.lastOnlineAt,
    this.offlineStartedAt,
  });

  final StateObservation<ConnectivityType> connectivity;
  final StateObservation<InternetReachability> internet;
  final StateObservation<NetworkOnlineStatus> status;
  final DateTime? lastOnlineAt;
  final DateTime? offlineStartedAt;
  final StateObservation<Duration> offlineDuration;

  /// Every component observation, used for availability derivation.
  Iterable<StateObservation<Object?>> get observations => [
    connectivity,
    internet,
    status,
    offlineDuration,
  ];

  DataFreshness freshnessAt(DateTime now) => status.freshnessAt(now);

  Map<String, Object?> toJson() => {
    'connectivity': connectivity.toJson(encodeValue: (value) => value.name),
    'internet': internet.toJson(encodeValue: (value) => value.name),
    'status': status.toJson(encodeValue: (value) => value.name),
    'lastOnlineAt': lastOnlineAt?.toUtc().toIso8601String(),
    'offlineStartedAt': offlineStartedAt?.toUtc().toIso8601String(),
    'offlineDuration': offlineDuration.toJson(
      encodeValue: (value) => value.inMilliseconds,
    ),
  };

  factory NetworkState.fromJson(Map<String, Object?> json) => NetworkState(
    connectivity: StateObservation<ConnectivityType>.fromJson(
      Map<String, Object?>.from(json['connectivity']! as Map),
      decodeValue: (value) => ConnectivityType.values.byName(value! as String),
    ),
    internet: StateObservation<InternetReachability>.fromJson(
      Map<String, Object?>.from(json['internet']! as Map),
      decodeValue: (value) => InternetReachability.values.byName(value! as String),
    ),
    status: StateObservation<NetworkOnlineStatus>.fromJson(
      Map<String, Object?>.from(json['status']! as Map),
      decodeValue: (value) => NetworkOnlineStatus.values.byName(value! as String),
    ),
    lastOnlineAt: _date(json['lastOnlineAt']),
    offlineStartedAt: _date(json['offlineStartedAt']),
    offlineDuration: StateObservation<Duration>.fromJson(
      Map<String, Object?>.from(json['offlineDuration']! as Map),
      decodeValue: (value) => Duration(milliseconds: value! as int),
    ),
  );

  static DateTime? _date(Object? value) => value == null
      ? null
      : DateTime.parse(value as String).toUtc();

  static const unknown = NetworkState(
    connectivity: StateObservation<ConnectivityType>(
      availability: CapabilityAvailability.unknown,
    ),
    internet: StateObservation<InternetReachability>(
      availability: CapabilityAvailability.unknown,
    ),
    status: StateObservation<NetworkOnlineStatus>(
      availability: CapabilityAvailability.unknown,
      value: NetworkOnlineStatus.unknown,
    ),
    offlineDuration: StateObservation<Duration>(
      availability: CapabilityAvailability.unknown,
    ),
  );
}
