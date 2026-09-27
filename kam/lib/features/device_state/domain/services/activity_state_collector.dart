import 'dart:async';

import '../../../../core/domain/device_metric.dart';
import '../models/activity_state.dart';
import '../models/device_state_snapshot.dart';
import '../sources/activity_platform_source.dart';
import 'activity_observation_store.dart';

/// Collects only signals the platform genuinely exposes: the device display
/// state where supported, and this application's own lifecycle as reported by
/// Flutter.
///
/// Core rules enforced here:
///
/// * [lastObservedActivityAt] is written **only** when a supported signal
///   event is actually observed (a screen on/off transition or an observed
///   app-lifecycle transition). A plain refresh, an application restart or a
///   restored historical value never fabricates a new timestamp.
/// * Activity duration is known only after an observed transition into the
///   detected state; otherwise it stays `unknown`. A lifecycle/monitoring gap
///   invalidates the session because transitions may have been missed.
/// * A failed display read becomes an error observation for the display
///   alone; lifecycle, battery and network observations are untouched.
/// * There is no polling loop: native events and pushed lifecycle reports are
///   the only triggers, with one on-demand `refresh()`.
class ActivityStateCollector {
  ActivityStateCollector({
    required this.gateway,
    required this.store,
    required this.now,
  });

  final ActivityPlatformGateway gateway;
  final ActivityObservationStore store;
  final DateTime Function() now;

  final _updates = StreamController<ActivityState>.broadcast();
  StreamSubscription<Object?>? _nativeSubscription;
  Future<void>? _restoreTask;

  ActivityState _current = ActivityState.unknown;
  DeviceScreenState? _previousScreen;
  bool? _previousDetected;
  AppLifecyclePhase? _lifecyclePhase;
  DateTime? _lifecycleObservedAt;
  DateTime? _lastObservedActivityAt;
  DateTime? _activityStartedAt;
  Stopwatch? _activityStopwatch;

  ActivityState get current => _current;
  bool get isStarted => _nativeSubscription != null;
  Stream<ActivityState> get updates => _updates.stream;

  /// Most recent observed signal event (including restored history), or
  /// `null` when none has been observed.
  DateTime? get lastObservedActivityAt => _lastObservedActivityAt;

  /// The display state is observable only on Android; iOS exposes no public
  /// screen on/off API to third-party apps and must remain `unsupported`
  /// rather than approximated. The app lifecycle comes from the Flutter
  /// framework itself, so it is supported on every platform.
  bool get _screenSupported => gateway.platformName == 'android';

  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus => {
    DeviceMetric.screenState: DeviceCapabilityStatus(
      _screenSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    ),
    DeviceMetric.activityState: const DeviceCapabilityStatus(
      CapabilitySupport.supported,
    ),
    DeviceMetric.lastActivity: const DeviceCapabilityStatus(
      CapabilitySupport.supported,
    ),
    DeviceMetric.appLifecycle: const DeviceCapabilityStatus(
      CapabilitySupport.supported,
    ),
    DeviceMetric.deviceAvailability: const DeviceCapabilityStatus(
      CapabilitySupport.supported,
    ),
  };

  /// Reads the current display state once without starting the event stream.
  Future<ActivityState> refresh() async {
    await _restoreLastObservedActivity();
    if (!_screenSupported) {
      return _publishWithoutScreenRead();
    }
    try {
      return _consumeScreen(
        ActivityPlatformSample.fromPlatform(await gateway.readCurrent()),
      );
    } catch (error) {
      return _setError(error);
    }
  }

  /// Starts the native display event stream and refreshes the current reading.
  Future<void> start() async {
    if (_nativeSubscription != null) return;
    await _restoreLastObservedActivity();
    if (!_screenSupported) {
      _publishWithoutScreenRead();
      return;
    }
    try {
      _nativeSubscription = gateway.watchChanges().listen(
        (value) {
          try {
            _consumeScreen(ActivityPlatformSample.fromPlatform(value));
          } catch (error) {
            _setError(error);
          }
        },
        onError: (Object error, StackTrace stack) => _setError(error),
        onDone: () {
          _nativeSubscription = null;
          _resetAfterObservationGap();
        },
      );
      await refresh();
    } catch (error) {
      _setError(error);
    }
  }

  /// Stops display observation. Lifecycle reports keep working; a later read
  /// must re-establish transition adjacency before duration is known again.
  Future<void> stop() async {
    final subscription = _nativeSubscription;
    _nativeSubscription = null;
    await subscription?.cancel();
    _resetAfterObservationGap();
  }

  Future<void> dispose() async {
    await stop();
    unawaited(_updates.close());
  }

  Stream<ActivityState> watchActivityState() async* {
    await start();
    yield _current;
    try {
      yield* _updates.stream;
    } finally {
      await stop();
    }
  }

  /// Records a lifecycle report pushed by the presentation layer.
  ///
  /// The first report only establishes the current phase; it is the app
  /// starting, not an observed activity event. A subsequent *observed
  /// transition* is a genuine platform signal and updates
  /// [lastObservedActivityAt].
  void reportAppLifecycle(AppLifecyclePhase phase) {
    final at = now().toUtc();
    final previous = _lifecyclePhase;
    _lifecyclePhase = phase;
    _lifecycleObservedAt = at;
    if (previous != null && previous != phase) {
      _noteActivitySignal(at);
    }
    _publish(_current.screenState, at);
  }

  ActivityState _consumeScreen(ActivityPlatformSample sample) {
    final at = now().toUtc();
    _reconfirmForeground(at);
    final screen = _screenObservation(sample, at);
    _observeScreenTransition(screen, at);
    return _publish(screen, at);
  }

  ActivityState _publishWithoutScreenRead() {
    final at = now().toUtc();
    _reconfirmForeground(at);
    return _publish(_screenUnsupported(), at);
  }

  /// While a refresh runs in the foreground, the app's own foreground state is
  /// directly observable (Dart code is executing in the foreground), so the
  /// lifecycle observation is re-stamped. This touches only the lifecycle
  /// observation — never `lastObservedActivityAt`.
  void _reconfirmForeground(DateTime at) {
    if (_lifecyclePhase == AppLifecyclePhase.foreground) {
      _lifecycleObservedAt = at;
    }
  }

  ActivityState _publish(
    StateObservation<DeviceScreenState> screen,
    DateTime at,
  ) {
    final lifecycle = _lifecycleObservation();
    final detected = _detect(screen, lifecycle);
    _updateSession(detected, at);
    final status = StateObservation<ActivityStatus>(
      availability: detected == null
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: detected ?? ActivityStatus.unknown,
      observedAt: at,
      updatedAt: at,
      source: 'derived_activity',
      platform: gateway.platformName,
    );
    final duration = _duration(detected, at);
    _current = ActivityState(
      screenState: screen,
      activityStatus: status,
      appLifecycle: lifecycle,
      activityDuration: duration,
      lastObservedActivityAt: _lastObservedActivityAt,
      activityStartedAt: _activityStartedAt,
    );
    _updates.add(_current);
    return _current;
  }

  StateObservation<DeviceScreenState> _screenObservation(
    ActivityPlatformSample sample,
    DateTime at,
  ) {
    if (!sample.screenStateSupported) return _screenUnsupported();
    final raw = sample.screenState;
    if (raw == null) {
      return StateObservation<DeviceScreenState>(
        availability: CapabilityAvailability.unavailable,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
      );
    }
    final value = switch (raw) {
      'on' => DeviceScreenState.on,
      'off' => DeviceScreenState.off,
      'unknown' => DeviceScreenState.unknown,
      _ => null,
    };
    if (value == null) {
      return StateObservation<DeviceScreenState>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: gateway.platformName,
        platform: gateway.platformName,
        error: 'Unrecognized screen state.',
      );
    }
    return StateObservation<DeviceScreenState>(
      availability: value == DeviceScreenState.unknown
          ? CapabilityAvailability.unknown
          : CapabilityAvailability.available,
      value: value,
      observedAt: at,
      updatedAt: at,
      source: gateway.platformName,
      platform: gateway.platformName,
    );
  }

  StateObservation<DeviceScreenState> _screenUnsupported() =>
      StateObservation<DeviceScreenState>(
        availability: CapabilityAvailability.unsupported,
        source: gateway.platformName,
        platform: gateway.platformName,
      );

  /// Updates `lastObservedActivityAt` only when two real observations show a
  /// transition. A first read of an already-active signal is not a transition
  /// and must not invent a timestamp.
  void _observeScreenTransition(
    StateObservation<DeviceScreenState> screen,
    DateTime at,
  ) {
    if (screen.availability != CapabilityAvailability.available) return;
    final value = screen.value;
    if (value == null) return;
    final previous = _previousScreen;
    _previousScreen = value;
    if (previous != null && previous != value) {
      _noteActivitySignal(at);
    }
  }

  StateObservation<AppLifecyclePhase> _lifecycleObservation() {
    final phase = _lifecyclePhase;
    final at = _lifecycleObservedAt;
    if (phase == null || at == null) {
      return const StateObservation<AppLifecyclePhase>(
        availability: CapabilityAvailability.unknown,
        source: 'app_lifecycle',
      );
    }
    return StateObservation<AppLifecyclePhase>(
      availability: CapabilityAvailability.available,
      value: phase,
      observedAt: at,
      updatedAt: at,
      source: 'app_lifecycle',
    );
  }

  /// Derives the signal status from whichever signals are actually available.
  /// Returns `null` when no signal can say anything.
  ActivityStatus? _detect(
    StateObservation<DeviceScreenState> screen,
    StateObservation<AppLifecyclePhase> lifecycle,
  ) {
    final active = <bool>[];
    final screenValue = screen.availability == CapabilityAvailability.available
        ? screen.value
        : null;
    if (screenValue != null && screenValue != DeviceScreenState.unknown) {
      active.add(screenValue == DeviceScreenState.on);
    }
    if (lifecycle.availability == CapabilityAvailability.available &&
        lifecycle.value != null) {
      active.add(lifecycle.value == AppLifecyclePhase.foreground);
    }
    if (active.isEmpty) return null;
    return active.contains(true)
        ? ActivityStatus.activityDetected
        : ActivityStatus.noActivityObserved;
  }

  /// Tracks the detected-state session across observed transitions only.
  void _updateSession(ActivityStatus? detected, DateTime at) {
    if (detected == null) return;
    if (detected == ActivityStatus.activityDetected) {
      if (_previousDetected == false) {
        _activityStartedAt = at;
        _activityStopwatch = Stopwatch()..start();
      }
      // An unknown previous state gives no observed start, so the duration
      // stays unknown rather than being anchored to this moment.
    } else {
      if (_previousDetected == true) {
        _clearSession();
      }
    }
    _previousDetected = detected == ActivityStatus.activityDetected;
  }

  StateObservation<Duration> _duration(ActivityStatus? detected, DateTime at) {
    const source = 'observed_transition';
    if (detected == null) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: source,
        platform: gateway.platformName,
      );
    }
    if (detected != ActivityStatus.activityDetected) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unavailable,
        observedAt: at,
        source: source,
        platform: gateway.platformName,
      );
    }
    final startedAt = _activityStartedAt;
    final stopwatch = _activityStopwatch;
    if (startedAt == null || stopwatch == null) {
      return StateObservation<Duration>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: source,
        platform: gateway.platformName,
      );
    }
    final elapsed = stopwatch.elapsed;
    if (elapsed.isNegative || elapsed > const Duration(days: 30)) {
      _clearSession();
      return StateObservation<Duration>(
        availability: CapabilityAvailability.error,
        observedAt: at,
        source: 'monotonic_clock',
        platform: gateway.platformName,
        error: 'Activity duration exceeded the defensive maximum.',
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

  ActivityState _setError(Object error) {
    _clearSession();
    _previousDetected = null;
    final at = now().toUtc();
    final screen = StateObservation<DeviceScreenState>(
      availability: CapabilityAvailability.error,
      observedAt: at,
      source: gateway.platformName,
      platform: gateway.platformName,
      error: 'Screen read failed (${error.runtimeType}).',
    );
    return _publish(screen, at);
  }

  void _noteActivitySignal(DateTime at) {
    _lastObservedActivityAt = at;
    unawaited(_persistLastObservedActivity(at));
  }

  Future<void> _persistLastObservedActivity(DateTime value) async {
    try {
      await store.writeLastObservedActivityAt(value);
    } catch (_) {
      // Persistence failure must not invalidate a successful observation.
    }
  }

  Future<void> _restoreLastObservedActivity() => _restoreTask ??= () async {
    if (_lastObservedActivityAt != null) return;
    try {
      final stored = await store.readLastObservedActivityAt();
      final timestamp = stored?.toUtc();
      if (_lastObservedActivityAt == null &&
          timestamp != null &&
          !timestamp.isAfter(now().toUtc())) {
        _lastObservedActivityAt = timestamp;
      }
    } catch (_) {
      // Storage is optional; historical time remains unknown if unavailable.
    }
  }();

  void _resetAfterObservationGap() {
    // Across a gap, adjacency can no longer be assumed: no transition may be
    // claimed between readings taken on either side of it, and any in-progress
    // duration must not claim continuity.
    _previousScreen = null;
    _previousDetected = null;
    _clearSession();
  }

  void _clearSession() {
    _activityStartedAt = null;
    _activityStopwatch?.stop();
    _activityStopwatch = null;
  }
}
