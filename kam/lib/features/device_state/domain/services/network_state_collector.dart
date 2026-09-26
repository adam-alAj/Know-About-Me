import 'dart:async';

import '../../../../core/domain/device_metric.dart';
import '../models/device_state_snapshot.dart';
import '../models/network_state.dart';
import '../sources/network_platform_source.dart';
import 'network_observation_store.dart';

/// Normalizes platform network observations and tracks transitions only while
/// observations are active. No background polling or Firebase reachability
/// inference is performed.
class NetworkStateCollector {
  NetworkStateCollector({
    required this.gateway,
    required this.now,
    required this.store,
  });

  final NetworkPlatformGateway gateway;
  final DateTime Function() now;
  final NetworkObservationStore store;

  final _updates = StreamController<NetworkState>.broadcast();
  StreamSubscription<Object?>? _nativeSubscription;
  Future<void>? _restoreTask;
  NetworkState _current = NetworkState.unknown;
  NetworkOnlineStatus? _previousStatus;
  DateTime? _lastOnlineAt;
  DateTime? _offlineStartedAt;
  Stopwatch? _offlineStopwatch;

  NetworkState get current => _current;
  bool get isStarted => _nativeSubscription != null;
  Stream<NetworkState> get updates => _updates.stream;

  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus => {
    DeviceMetric.networkStatus: DeviceCapabilityStatus(
      _isSupportedPlatform
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    ),
    DeviceMetric.offlineDuration: DeviceCapabilityStatus(
      _isSupportedPlatform
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    ),
    DeviceMetric.networkConnectivity: DeviceCapabilityStatus(
      _isSupportedPlatform
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    ),
    DeviceMetric.internetReachability: DeviceCapabilityStatus(
      gateway.platformName == 'android'
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    ),
  };

  Future<NetworkState> refresh() async {
    if (!_isSupportedPlatform) return _setUnsupported();
    await _restoreLastOnline();
    try {
      return _consume(NetworkPlatformSample.fromPlatform(await gateway.readCurrent()));
    } catch (error) {
      return _setError(error);
    }
  }

  Future<void> start() async {
    if (_nativeSubscription != null || !_isSupportedPlatform) {
      if (!_isSupportedPlatform) _setUnsupported();
      return;
    }
    await _restoreLastOnline();
    try {
      _nativeSubscription = gateway.watchChanges().listen(
        (value) {
          try {
            _consume(NetworkPlatformSample.fromPlatform(value));
          } catch (error) {
            _setError(error);
          }
        },
        onError: (Object error, StackTrace stack) => _setError(error),
        onDone: () {
          _nativeSubscription = null;
          _resetOfflineSession();
          _previousStatus = null;
        },
      );
      await refresh();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> stop() async {
    final subscription = _nativeSubscription;
    _nativeSubscription = null;
    await subscription?.cancel();
    // A lifecycle gap can hide a transition. Preserve last-online history but
    // discard any in-progress offline duration and transition baseline.
    _resetOfflineSession();
    _previousStatus = null;
  }

  Future<void> dispose() async {
    await stop();
    unawaited(_updates.close());
  }

  Stream<NetworkState> watchNetworkState() async* {
    await start();
    yield _current;
    try {
      yield* _updates.stream;
    } finally {
      await stop();
    }
  }

  bool get _isSupportedPlatform =>
      gateway.platformName == 'android' || gateway.platformName == 'ios';

  Future<void> _restoreLastOnline() => _restoreTask ??= () async {
    try {
      final stored = await store.readLastOnlineAt();
      final timestamp = stored?.toUtc();
      if (timestamp != null && !timestamp.isAfter(now().toUtc())) {
        _lastOnlineAt = timestamp;
      }
    } catch (_) {
      // Storage is optional; historical time remains unknown if unavailable.
    }
  }();

  NetworkState _consume(NetworkPlatformSample sample) {
    final observedAt = now().toUtc();
    final connectivity = _connectivity(sample.connectivityType, observedAt);
    final internet = _internet(sample.internetReachability, observedAt);
    final status = _status(sample.onlineStatus, observedAt);
    final next = status.value;

    if (status.availability == CapabilityAvailability.available &&
        next == NetworkOnlineStatus.online) {
      if (_previousStatus != NetworkOnlineStatus.online) {
        _lastOnlineAt = observedAt;
        unawaited(_persistLastOnline(observedAt));
      }
      _resetOfflineSession();
    } else if (status.availability == CapabilityAvailability.available &&
        next == NetworkOnlineStatus.offline) {
      if (_previousStatus == NetworkOnlineStatus.online) {
        _offlineStartedAt = observedAt;
        _offlineStopwatch = Stopwatch()..start();
      } else if (_previousStatus != NetworkOnlineStatus.offline) {
        // First observation after startup/resume cannot establish how long the
        // device was already offline.
        _resetOfflineSession();
      }
    } else {
      _resetOfflineSession();
    }

    if (status.availability == CapabilityAvailability.available && next != null) {
      _previousStatus = next == NetworkOnlineStatus.unknown ? null : next;
    } else {
      _previousStatus = null;
    }

    final duration = _offlineDuration(status, observedAt);
    _current = NetworkState(
      connectivity: connectivity,
      internet: internet,
      status: status,
      lastOnlineAt: _lastOnlineAt,
      offlineStartedAt: _offlineStartedAt,
      offlineDuration: duration,
    );
    _updates.add(_current);
    return _current;
  }

  Future<void> _persistLastOnline(DateTime value) async {
    try {
      await store.writeLastOnlineAt(value);
    } catch (_) {
      // Persistence failure must not invalidate a successful local observation.
    }
  }

  StateObservation<ConnectivityType> _connectivity(
    String? raw,
    DateTime at,
  ) {
    if (raw == null) {
      return StateObservation<ConnectivityType>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
      );
    }
    final value = switch (raw) {
      'wifi' => ConnectivityType.wifi,
      'mobile' => ConnectivityType.mobile,
      'ethernet' => ConnectivityType.ethernet,
      'bluetooth' => ConnectivityType.bluetooth,
      'vpn' => ConnectivityType.vpn,
      'none' => ConnectivityType.none,
      'unknown' => ConnectivityType.unknown,
      _ => null,
    };
    return StateObservation<ConnectivityType>(
      availability: value == null
          ? CapabilityAvailability.error
          : value == ConnectivityType.unknown
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: value,
      observedAt: at,
      updatedAt: at,
      source: gateway.platformName,
      platform: gateway.platformName,
      error: value == null ? 'Unrecognized connectivity type.' : null,
    );
  }

  StateObservation<InternetReachability> _internet(String? raw, DateTime at) {
    final value = switch (raw) {
      'available' => InternetReachability.available,
      'unavailable' => InternetReachability.unavailable,
      'unknown' => InternetReachability.unknown,
      _ => null,
    };
    return StateObservation<InternetReachability>(
      availability: value == null
          ? CapabilityAvailability.unknown
          : value == InternetReachability.unknown
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: value,
      observedAt: at,
      updatedAt: at,
      source: gateway.platformName,
      platform: gateway.platformName,
    );
  }

  StateObservation<NetworkOnlineStatus> _status(String? raw, DateTime at) {
    final value = switch (raw) {
      'online' => NetworkOnlineStatus.online,
      'offline' => NetworkOnlineStatus.offline,
      'unknown' => NetworkOnlineStatus.unknown,
      _ => null,
    };
    return StateObservation<NetworkOnlineStatus>(
      availability: value == null
          ? CapabilityAvailability.error
          : value == NetworkOnlineStatus.unknown
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: value,
      observedAt: at,
      updatedAt: at,
      source: gateway.platformName,
      platform: gateway.platformName,
      error: value == null ? 'Unrecognized network status.' : null,
    );
  }

  StateObservation<Duration> _offlineDuration(
    StateObservation<NetworkOnlineStatus> status,
    DateTime at,
  ) {
    if (status.value != NetworkOnlineStatus.offline ||
        status.availability != CapabilityAvailability.available) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unavailable,
        observedAt: at,
        source: 'observed_transition',
        platform: gateway.platformName,
      );
    }
    final start = _offlineStartedAt;
    final stopwatch = _offlineStopwatch;
    if (start == null || stopwatch == null || start.isAfter(at)) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: 'observed_transition',
        platform: gateway.platformName,
      );
    }
    final elapsed = stopwatch.elapsed;
    if (elapsed.isNegative || elapsed > const Duration(days: 30)) {
      _resetOfflineSession();
      return StateObservation<Duration>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: 'monotonic_clock',
        platform: gateway.platformName,
        error: 'Offline duration exceeded the defensive maximum.',
      );
    }
    return StateObservation<Duration>(
      availability: CapabilityAvailability.available,
      value: elapsed,
      observedAt: at,
      updatedAt: at,
      source: 'monotonic_clock',
      platform: gateway.platformName,
    );
  }

  NetworkState _setError(Object error) {
    _resetOfflineSession();
    _previousStatus = null;
    final at = now().toUtc();
    final message = 'Network collection failed (${error.runtimeType}).';
    _current = NetworkState(
      connectivity: StateObservation<ConnectivityType>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: message,
      ),
      internet: StateObservation<InternetReachability>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: message,
      ),
      status: StateObservation<NetworkOnlineStatus>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: message,
      ),
      lastOnlineAt: _lastOnlineAt,
      offlineDuration: StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: 'observed_transition',
        platform: gateway.platformName,
      ),
    );
    _updates.add(_current);
    return _current;
  }

  NetworkState _setUnsupported() {
    _resetOfflineSession();
    _previousStatus = null;
    _current = const NetworkState(
      connectivity: StateObservation<ConnectivityType>(
        availability: CapabilityAvailability.unsupported,
      ),
      internet: StateObservation<InternetReachability>(
        availability: CapabilityAvailability.unsupported,
      ),
      status: StateObservation<NetworkOnlineStatus>(
        availability: CapabilityAvailability.unsupported,
      ),
      offlineDuration: StateObservation<Duration>(
        availability: CapabilityAvailability.unsupported,
      ),
    );
    return _current;
  }

  void _resetOfflineSession() {
    _offlineStartedAt = null;
    _offlineStopwatch?.stop();
    _offlineStopwatch = null;
  }
}
