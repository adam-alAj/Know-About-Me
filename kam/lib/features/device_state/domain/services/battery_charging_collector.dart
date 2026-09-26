import 'dart:async';

import '../models/battery_state.dart';
import '../models/device_state_snapshot.dart';
import '../../../../core/domain/device_metric.dart';
import '../sources/battery_platform_source.dart';

/// Validates native readings and tracks only charging transitions observed by
/// this collector instance. No historical start time is inferred on startup.
class BatteryChargingCollector {
  BatteryChargingCollector({
    required this.gateway,
    required this.now,
  });

  final BatteryPlatformGateway gateway;
  final DateTime Function() now;
  final _updates = StreamController<BatteryState>.broadcast();
  StreamSubscription<Object?>? _nativeSubscription;
  BatteryState _current = BatteryState.unknown;
  BatteryChargingState? _previousState;
  DateTime? _chargingStartedAt;
  Stopwatch? _chargingStopwatch;

  BatteryState get current => _current;
  bool get isStarted => _nativeSubscription != null;
  Stream<BatteryState> get updates => _updates.stream;

  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus {
    final mobile = _isSupportedPlatform;
    return {
      DeviceMetric.batteryPercentage: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
      DeviceMetric.chargingState: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
      DeviceMetric.chargingDuration: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
      DeviceMetric.chargingSource: DeviceCapabilityStatus(
        gateway.platformName == 'android'
            ? CapabilitySupport.supported
            : CapabilitySupport.unsupported,
      ),
    };
  }

  /// Read once without starting the event stream.
  Future<BatteryState> refresh() async {
    if (!_isSupportedPlatform) return _setUnsupported();
    try {
      return _consume(BatteryPlatformSample.fromPlatform(await gateway.readCurrent()));
    } catch (error) {
      return _setError(error);
    }
  }

  /// Starts the native event stream and refreshes the current reading.
  Future<void> start() async {
    if (_nativeSubscription != null) return;
    if (!_isSupportedPlatform) {
      _setUnsupported();
      return;
    }
    try {
      _nativeSubscription = gateway.watchChanges().listen(
        (value) {
          try {
            _consume(BatteryPlatformSample.fromPlatform(value));
          } catch (error) {
            _setError(error);
          }
        },
        onError: (Object error, StackTrace stack) => _setError(error),
        onDone: () {
          _nativeSubscription = null;
          _clearSession();
          _previousState = null;
        },
      );
      await refresh();
    } catch (error) {
      _setError(error);
    }
  }

  /// Stops event observation. Native receiver/notification listeners are
  /// released by the platform stream's cancellation handler.
  Future<void> stop() async {
    final subscription = _nativeSubscription;
    _nativeSubscription = null;
    await subscription?.cancel();
    // While observation is stopped, charging transitions may be missed.
    // A later read must establish a new transition before duration is known.
    _clearSession();
    _previousState = null;
  }

  Future<void> dispose() async {
    await stop();
    unawaited(_updates.close());
  }

  bool get _isSupportedPlatform =>
      gateway.platformName == 'android' || gateway.platformName == 'ios';

  /// Emits the current reading, then native state/level change events.
  Stream<BatteryState> watchBatteryState() async* {
    await start();
    yield _current;
    try {
      yield* _updates.stream;
    } finally {
      await stop();
    }
  }

  BatteryState _consume(BatteryPlatformSample sample) {
    final observedAt = now().toUtc();
    final percentage = _percentage(sample.percentage, observedAt);
    final chargingState = _chargingState(sample.chargingState, observedAt);
    final chargingSource = _chargingSource(sample, observedAt);
    final next = chargingState.value;

    if (chargingState.availability != CapabilityAvailability.available ||
        next == null ||
        next == BatteryChargingState.unknown) {
      _clearSession();
    } else if (next == BatteryChargingState.charging) {
      final previous = _previousState;
      if (_chargingStartedAt == null &&
          (previous == BatteryChargingState.discharging ||
              previous == BatteryChargingState.notCharging)) {
        _chargingStartedAt = observedAt;
        _chargingStopwatch = Stopwatch()..start();
      }
    } else if (next == BatteryChargingState.full) {
      // Preserve a known session if charging-to-full was observed, but a first
      // reading of full does not reveal when the session began.
      if (_previousState != BatteryChargingState.charging &&
          _previousState != BatteryChargingState.full) {
        _clearSession();
      }
    } else {
      _clearSession();
    }

    final duration = _duration(observedAt, chargingState);
    if (chargingState.availability == CapabilityAvailability.available &&
        next != null) {
      _previousState = next;
    } else {
      _previousState = null;
    }

    _current = BatteryState(
      percentage: percentage,
      chargingState: chargingState,
      chargingDuration: duration,
      chargingSource: chargingSource,
      chargingStartedAt: _chargingStartedAt,
    );
    _updates.add(_current);
    return _current;
  }

  StateObservation<int> _percentage(Object? value, DateTime observedAt) {
    if (value == null) {
      return StateObservation<int>(
        availability: CapabilityAvailability.unavailable,
        observedAt: observedAt,
        source: gateway.platformName,
        platform: gateway.platformName,
      );
    }
    if (value is! int || value < 0 || value > 100) {
      return StateObservation<int>(
        availability: CapabilityAvailability.error,
        observedAt: observedAt,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: 'Battery percentage was outside the valid 0–100 range.',
      );
    }
    return StateObservation<int>(
      availability: CapabilityAvailability.available,
      value: value,
      observedAt: observedAt,
      updatedAt: observedAt,
      source: gateway.platformName,
      platform: gateway.platformName,
    );
  }

  StateObservation<BatteryChargingState> _chargingState(
    String? value,
    DateTime observedAt,
  ) {
    if (value == null) {
      return StateObservation<BatteryChargingState>(
        availability: CapabilityAvailability.unavailable,
        observedAt: observedAt,
        source: gateway.platformName,
        platform: gateway.platformName,
      );
    }
    final normalized = switch (value) {
      'charging' => BatteryChargingState.charging,
      'full' => BatteryChargingState.full,
      'discharging' => BatteryChargingState.discharging,
      'notCharging' => BatteryChargingState.notCharging,
      'unknown' => BatteryChargingState.unknown,
      _ => null,
    };
    return StateObservation<BatteryChargingState>(
      availability: normalized == null
          ? CapabilityAvailability.error
          : normalized == BatteryChargingState.unknown
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: normalized,
      observedAt: observedAt,
      updatedAt: observedAt,
      source: gateway.platformName,
      platform: gateway.platformName,
      error: normalized == null ? 'Unrecognized charging state.' : null,
    );
  }

  StateObservation<BatteryChargingSource> _chargingSource(
    BatteryPlatformSample sample,
    DateTime observedAt,
  ) {
    if (!sample.chargingSourceSupported) {
      return StateObservation<BatteryChargingSource>(
        availability: CapabilityAvailability.unsupported,
        source: gateway.platformName,
        platform: gateway.platformName,
      );
    }
    final normalized = switch (sample.chargingSource) {
      'usb' => BatteryChargingSource.usb,
      'ac' => BatteryChargingSource.ac,
      'wireless' => BatteryChargingSource.wireless,
      'unknown' => BatteryChargingSource.unknown,
      _ => null,
    };
    return StateObservation<BatteryChargingSource>(
      availability: normalized == null
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: normalized,
      observedAt: observedAt,
      source: gateway.platformName,
      platform: gateway.platformName,
      error: null,
    );
  }

  StateObservation<Duration> _duration(
    DateTime observedAt,
    StateObservation<BatteryChargingState> charging,
  ) {
    final state = charging.value;
    if (charging.availability != CapabilityAvailability.available ||
        (state != BatteryChargingState.charging &&
            state != BatteryChargingState.full)) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unavailable,
        observedAt: observedAt,
        source: 'observed_transition',
        platform: gateway.platformName,
      );
    }
    final startedAt = _chargingStartedAt;
    final stopwatch = _chargingStopwatch;
    if (startedAt == null || stopwatch == null) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: observedAt,
        source: 'observed_transition',
        platform: gateway.platformName,
      );
    }
    final duration = stopwatch.elapsed;
    if (duration.isNegative || duration > const Duration(days: 30)) {
      _clearSession();
      return StateObservation<Duration>(
        availability: CapabilityAvailability.error,
        observedAt: observedAt,
        source: 'monotonic_clock',
        platform: gateway.platformName,
        error: 'Charging duration exceeded the defensive maximum.',
      );
    }
    return StateObservation<Duration>(
      availability: CapabilityAvailability.available,
      value: duration,
      observedAt: observedAt,
      updatedAt: observedAt,
      source: 'monotonic_clock',
      platform: gateway.platformName,
    );
  }

  BatteryState _setError(Object error) {
    _clearSession();
    _previousState = null;
    final timestamp = now().toUtc();
    _current = BatteryState(
      percentage: StateObservation<int>(
        availability: CapabilityAvailability.error,
        observedAt: timestamp,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: 'Battery read failed (${error.runtimeType}).',
      ),
      chargingState: StateObservation<BatteryChargingState>(
        availability: CapabilityAvailability.error,
        observedAt: timestamp,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: 'Battery read failed (${error.runtimeType}).',
      ),
      chargingDuration: StateObservation<Duration>(
        availability: CapabilityAvailability.unavailable,
        source: 'observed_transition',
        platform: gateway.platformName,
      ),
      chargingSource: StateObservation<BatteryChargingSource>(
        availability: CapabilityAvailability.unknown,
        source: gateway.platformName,
        platform: gateway.platformName,
      ),
    );
    _updates.add(_current);
    return _current;
  }

  BatteryState _setUnsupported() {
    _clearSession();
    _previousState = null;
    _current = const BatteryState(
      percentage: StateObservation<int>(
        availability: CapabilityAvailability.unsupported,
      ),
      chargingState: StateObservation<BatteryChargingState>(
        availability: CapabilityAvailability.unsupported,
      ),
      chargingDuration: StateObservation<Duration>(
        availability: CapabilityAvailability.unsupported,
      ),
      chargingSource: StateObservation<BatteryChargingSource>(
        availability: CapabilityAvailability.unsupported,
      ),
    );
    return _current;
  }

  void _clearSession() {
    _chargingStartedAt = null;
    _chargingStopwatch?.stop();
    _chargingStopwatch = null;
  }
}
