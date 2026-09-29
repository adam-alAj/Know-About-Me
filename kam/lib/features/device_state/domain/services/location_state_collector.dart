import 'dart:async';

import '../../../../core/domain/device_metric.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../../location/domain/models/location_state.dart';
import '../../../location/domain/services/home_presence_calculator.dart';
import '../models/device_location_state.dart';
import '../models/device_state_snapshot.dart';
import '../sources/location_platform_source.dart';
import 'location_observation_store.dart';

/// Normalizes location into the device-state vocabulary (Phase 10).
///
/// Rules enforced here:
///
/// * Permission, disabled location services and "no fix" are distinct states;
///   they never collapse into a single `null` location.
/// * A fix keeps the platform's own timestamp. Restoring a stored fix does not
///   make it current: it is reported with its real age and becomes `stale`.
/// * At-home/away is only produced from a usable fix plus an explicitly
///   user-configured home; an unavailable location yields `unknown`, never
///   `awayFromHome`.
/// * Home is never inferred — it is supplied by the profile and only the
///   derived distance/presence are published.
/// * Collection is event-driven and throttled: one fix per refresh, plus
///   platform-throttled updates while monitoring is active. No polling loop,
///   no background tracking.
class LocationStateCollector {
  LocationStateCollector({
    required this.gateway,
    required this.store,
    required this.now,
  });

  final LocationPlatformGateway gateway;
  final LocationObservationStore store;
  final DateTime Function() now;

  static const _calculator = HomePresenceCalculator();

  final _updates = StreamController<DeviceLocationState>.broadcast();
  StreamSubscription<Object?>? _nativeSubscription;
  Future<void>? _restoreTask;

  DeviceLocationState _current = DeviceLocationState.unknown;
  HomeLocation? _home;
  LocationFix? _lastKnownFix;
  DevicePermissionState _permission = DevicePermissionState.unknown;
  bool _precise = false;
  bool? _serviceEnabled;
  bool _unsupported = false;
  String? _statusError;
  String? _fixError;
  bool _wantSubscription = false;

  DeviceLocationState get current => _current;
  bool get isStarted => _nativeSubscription != null;
  Stream<DeviceLocationState> get updates => _updates.stream;

  /// The newest fix this device has observed, live or restored.
  LocationFix? get lastKnownFix => _lastKnownFix;

  bool get _platformSupported =>
      gateway.platformName == 'android';

  bool get _canObserve =>
      _platformSupported &&
      !_unsupported &&
      _permission == DevicePermissionState.granted &&
      _serviceEnabled == true;

  /// Capability registry entries. `backgroundLocation` is reported
  /// `unsupported` because this phase intentionally provides no background
  /// tracking; `preciseLocation` stays `permissionRequired` while only
  /// approximate location has been granted.
  Map<DeviceMetric, DeviceCapabilityStatus> get capabilityStatus {
    final mobile = _platformSupported && !_unsupported;
    final granted = _permission == DevicePermissionState.granted;
    return {
      DeviceMetric.location: DeviceCapabilityStatus(
        !mobile
            ? CapabilitySupport.unsupported
            : granted
            ? CapabilitySupport.supported
            : CapabilitySupport.permissionRequired,
        permission: mobile ? _permission : DevicePermissionState.notApplicable,
      ),
      DeviceMetric.preciseLocation: DeviceCapabilityStatus(
        !mobile
            ? CapabilitySupport.unsupported
            : granted && _precise
            ? CapabilitySupport.supported
            : CapabilitySupport.permissionRequired,
        permission: mobile ? _permission : DevicePermissionState.notApplicable,
      ),
      DeviceMetric.approximateLocation: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
      DeviceMetric.backgroundLocation: const DeviceCapabilityStatus(
        CapabilitySupport.unsupported,
      ),
      DeviceMetric.homeLocation: const DeviceCapabilityStatus(
        CapabilitySupport.supported,
      ),
      DeviceMetric.distanceFromHome: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
      DeviceMetric.homePresence: DeviceCapabilityStatus(
        mobile ? CapabilitySupport.supported : CapabilitySupport.unsupported,
      ),
    };
  }

  /// Reads permission/service state and, when allowed, one location fix.
  Future<DeviceLocationState> refresh() async {
    await _restoreLastKnownFix();
    await _readStatus();
    if (_canObserve) {
      await _readCurrentFix();
    }
    _syncSubscription();
    return _publish();
  }

  /// Asks the OS for location permission.
  ///
  /// Only called from an explicit user action. After a permanent refusal or an
  /// OS-level restriction the prompt is never shown again — the state simply
  /// reports `permanentlyDenied`/`restricted`.
  Future<DeviceLocationState> requestPermission() async {
    await _restoreLastKnownFix();
    if (!_platformSupported) return _publish();
    if (_permission == DevicePermissionState.permanentlyDenied ||
        _permission == DevicePermissionState.restricted) {
      await _readStatus();
      return _publish();
    }
    try {
      _applyStatus(
        LocationStatusSample.fromPlatform(await gateway.requestPermission()),
      );
    } catch (error) {
      _statusError = 'Location permission request failed (${error.runtimeType}).';
    }
    if (_canObserve) {
      await _readCurrentFix();
    }
    _syncSubscription();
    return _publish();
  }

  /// Starts observation: reads the current picture and subscribes to
  /// throttled platform updates when permission and the service allow it.
  Future<void> start() async {
    _wantSubscription = true;
    await _restoreLastKnownFix();
    await _readStatus();
    if (_canObserve) {
      await _readCurrentFix();
    }
    _syncSubscription();
    _publish();
  }

  /// Stops native location updates. The last fix and its timestamp are kept.
  Future<void> stop() async {
    _wantSubscription = false;
    await _cancelSubscription();
  }

  Future<void> dispose() async {
    await stop();
    unawaited(_updates.close());
  }

  Stream<DeviceLocationState> watchLocationState() async* {
    await start();
    yield _current;
    try {
      yield* _updates.stream;
    } finally {
      await stop();
    }
  }

  /// Supplies the user's explicitly configured home location.
  ///
  /// A home change is a configuration change, not a movement event: dependent
  /// values are recalculated from the last fix without touching any
  /// observation timestamp.
  void setHomeLocation(HomeLocation? home) {
    _home = home;
    _publish();
  }

  // ---------------------------------------------------------------------
  // Collection
  // ---------------------------------------------------------------------

  Future<void> _readStatus() async {
    if (!_platformSupported) {
      _unsupported = true;
      _serviceEnabled = null;
      _statusError = null;
      return;
    }
    try {
      _applyStatus(
        LocationStatusSample.fromPlatform(await gateway.readStatus()),
      );
    } catch (error) {
      _statusError = 'Location status read failed (${error.runtimeType}).';
    }
  }

  void _applyStatus(LocationStatusSample sample) {
    _unsupported = !sample.supported;
    _permission = _permissionFrom(sample.permission);
    _precise = sample.precise;
    _serviceEnabled = sample.serviceEnabled;
    _statusError = null;
  }

  static DevicePermissionState _permissionFrom(String? raw) => switch (raw) {
    'granted' => DevicePermissionState.granted,
    'denied' => DevicePermissionState.denied,
    'permanentlyDenied' => DevicePermissionState.permanentlyDenied,
    'restricted' => DevicePermissionState.restricted,
    'limited' => DevicePermissionState.limited,
    'notDetermined' => DevicePermissionState.notDetermined,
    _ => DevicePermissionState.unknown,
  };

  Future<void> _readCurrentFix() async {
    try {
      _applyFix(
        LocationFixSample.fromPlatform(await gateway.readCurrentLocation()),
      );
    } catch (error) {
      _fixError = 'Location read failed (${error.runtimeType}).';
    }
  }

  /// Validates a raw fix. Invalid values are rejected — never clamped or
  /// repaired into a plausible position.
  void _applyFix(LocationFixSample sample) {
    final rawError = sample.error;
    if (rawError != null) {
      _fixError = switch (rawError) {
        'timeout' => 'Location request timed out.',
        'disabled' => 'Location services are disabled.',
        'denied' => 'Location permission was denied.',
        _ => 'Location provider returned no fix.',
      };
      return;
    }
    final latitude = sample.latitude;
    final longitude = sample.longitude;
    if (latitude == null || longitude == null) {
      _fixError = 'Location provider returned an incomplete fix.';
      return;
    }
    final coordinate = Coordinate(latitude: latitude, longitude: longitude);
    if (!coordinate.isValid) {
      _fixError = 'Location provider returned an invalid coordinate.';
      return;
    }
    final accuracy = sample.accuracyMeters;
    if (accuracy != null && (!accuracy.isFinite || accuracy < 0)) {
      _fixError = 'Location accuracy was outside the valid range.';
      return;
    }
    final fix = LocationFix(
      coordinate: coordinate,
      observedAt: _fixTimestamp(sample.observedAt),
      accuracyMeters: accuracy,
      approximate: sample.approximate,
      source: gateway.platformName,
    );
    _lastKnownFix = fix;
    _fixError = null;
    unawaited(_persistLastKnownFix(fix));
  }

  /// Uses the platform's own fix time, clamped to "now" if the platform clock
  /// ran ahead, so age arithmetic stays honest in both directions.
  DateTime _fixTimestamp(DateTime? platformTime) {
    final at = now().toUtc();
    if (platformTime == null) return at;
    final utc = platformTime.toUtc();
    return utc.isAfter(at) ? at : utc;
  }

  void _syncSubscription() {
    if (_canObserve && _wantSubscription) {
      _subscribe();
      return;
    }
    unawaited(_cancelSubscription());
  }

  void _subscribe() {
    if (_nativeSubscription != null) return;
    try {
      _nativeSubscription = gateway.watchChanges().listen(
        (value) {
          try {
            _applyFix(LocationFixSample.fromPlatform(value));
          } catch (error) {
            _fixError = 'Location update failed (${error.runtimeType}).';
          }
          _publish();
        },
        onError: (Object error, StackTrace stack) {
          _fixError = 'Location updates failed (${error.runtimeType}).';
          // A revoked permission or disabled service ends native delivery;
          // re-read the status so the state explains why.
          unawaited(_readStatus().then((_) {
            _syncSubscription();
            _publish();
          }));
        },
        onDone: () => _nativeSubscription = null,
      );
    } catch (error) {
      _fixError = 'Location updates are unavailable (${error.runtimeType}).';
    }
  }

  Future<void> _cancelSubscription() async {
    final subscription = _nativeSubscription;
    _nativeSubscription = null;
    await subscription?.cancel();
  }

  // ---------------------------------------------------------------------
  // Normalization
  // ---------------------------------------------------------------------

  DeviceLocationState _publish() {
    final at = now().toUtc();
    final fix = _lastKnownFix;
    final staleAge = fix == null
        ? null
        : FreshnessPolicy.location.classifyAge(_age(fix, at));
    final stale = staleAge == DataFreshness.stale;

    final home = _home;
    final usableHome = home != null && home.enabled && home.coordinate.isValid
        ? home
        : null;
    final homeUsable = usableHome != null;
    final distance = usableHome != null && fix != null
        ? _calculator.classify(
            home: usableHome,
            fix: fix.coordinate,
            accuracyMeters: fix.accuracyMeters,
          )
        : null;

    final location = _locationObservation(fix, at, stale: stale);
    _current = DeviceLocationState(
      location: location,
      lastKnownLocation: _lastKnownObservation(fix, at),
      permission: _permissionObservation(at),
      serviceState: _serviceState,
      distanceFromHome: _distanceObservation(
        distance,
        fix,
        at,
        stale: stale,
        homeUsable: homeUsable,
      ),
      presence: _presence(
        homeUsable: homeUsable,
        distance: distance,
        fix: fix,
        stale: stale,
      ),
      homeConfigured: home != null,
      homeEnabled: home?.enabled ?? false,
      homeRadiusMeters: home?.radiusMeters,
    );
    _updates.add(_current);
    return _current;
  }

  Duration _age(LocationFix fix, DateTime at) =>
      at.difference(fix.observedAt.toUtc());

  LocationServiceState get _serviceState {
    if (_unsupported) return LocationServiceState.unknown;
    final enabled = _serviceEnabled;
    if (enabled == null) return LocationServiceState.unknown;
    return enabled ? LocationServiceState.enabled : LocationServiceState.disabled;
  }

  StateObservation<LocationFix> _locationObservation(
    LocationFix? fix,
    DateTime at, {
    required bool stale,
  }) {
    if (_unsupported) {
      return const StateObservation<LocationFix>(
        availability: CapabilityAvailability.unsupported,
        source: 'location',
      );
    }
    final denial = _permissionDenial();
    if (denial != null) return denial;
    if (_serviceEnabled == false) {
      return StateObservation<LocationFix>(
        availability: CapabilityAvailability.serviceDisabled,
        observedAt: at,
        source: 'location',
        platform: gateway.platformName,
        permissionState: _permission,
        error: 'Location services are disabled on this device.',
      );
    }
    if (fix == null) {
      final error = _fixError ?? _statusError;
      if (error != null) {
        return StateObservation<LocationFix>(
          availability: CapabilityAvailability.error,
          observedAt: at,
          source: 'location',
          platform: gateway.platformName,
          permissionState: _permission,
          error: error,
        );
      }
      return StateObservation<LocationFix>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: 'location',
        platform: gateway.platformName,
        permissionState: _permission,
      );
    }
    return StateObservation<LocationFix>(
      availability: stale
          ? CapabilityAvailability.stale
          : CapabilityAvailability.available,
      value: fix,
      observedAt: fix.observedAt,
      updatedAt: at,
      source: fix.source,
      platform: gateway.platformName,
      permissionState: _permission,
    );
  }

  /// Present only when the app genuinely lacks access to location.
  StateObservation<LocationFix>? _permissionDenial() {
    final denied = switch (_permission) {
      DevicePermissionState.denied ||
      DevicePermissionState.permanentlyDenied ||
      DevicePermissionState.restricted ||
      DevicePermissionState.notDetermined ||
      DevicePermissionState.limited => true,
      _ => false,
    };
    if (!denied) return null;
    return StateObservation<LocationFix>(
      availability: CapabilityAvailability.permissionDenied,
      source: 'location',
      platform: gateway.platformName,
      permissionState: _permission,
      error: 'Location permission is not granted.',
    );
  }

  StateObservation<LocationFix> _lastKnownObservation(
    LocationFix? fix,
    DateTime at,
  ) {
    if (fix != null) {
      return StateObservation<LocationFix>(
        availability: CapabilityAvailability.available,
        value: fix,
        observedAt: fix.observedAt,
        updatedAt: at,
        source: fix.source,
        platform: gateway.platformName,
        permissionState: _permission,
      );
    }
    // No history: mirror the reason so the caller can explain it.
    final unavailable = _locationObservation(null, at, stale: false);
    return StateObservation<LocationFix>(
      availability: unavailable.availability,
      observedAt: unavailable.observedAt,
      source: 'location',
      platform: unavailable.platform,
      permissionState: unavailable.permissionState,
      error: unavailable.error,
    );
  }

  StateObservation<DevicePermissionState> _permissionObservation(DateTime at) {
    if (_unsupported) {
      return const StateObservation<DevicePermissionState>(
        availability: CapabilityAvailability.unsupported,
        source: 'location.permission',
      );
    }
    if (_statusError != null || _permission == DevicePermissionState.unknown) {
      return StateObservation<DevicePermissionState>(
        availability: CapabilityAvailability.unknown,
        value: _permission,
        observedAt: at,
        source: 'location.permission',
        platform: gateway.platformName,
        error: _statusError,
      );
    }
    return StateObservation<DevicePermissionState>(
      availability: CapabilityAvailability.available,
      value: _permission,
      observedAt: at,
      updatedAt: at,
      source: 'location.permission',
      platform: gateway.platformName,
    );
  }

  StateObservation<double> _distanceObservation(
    HomeDistanceResult? distance,
    LocationFix? fix,
    DateTime at, {
    required bool stale,
    required bool homeUsable,
  }) {
    if (_unsupported) {
      return const StateObservation<double>(
        availability: CapabilityAvailability.unsupported,
        source: 'location.distance',
      );
    }
    if (!homeUsable) {
      // No home configured, home disabled, or an invalid home coordinate: no
      // distance can be derived, and none is invented.
      return StateObservation<double>(
        availability: CapabilityAvailability.unavailable,
        observedAt: at,
        source: 'location.distance',
        platform: gateway.platformName,
        error: 'No enabled home location is configured.',
      );
    }
    if (distance == null || fix == null) {
      return StateObservation<double>(
        availability: CapabilityAvailability.unknown,
        observedAt: at,
        source: 'location.distance',
        platform: gateway.platformName,
        error: _fixError,
      );
    }
    return StateObservation<double>(
      availability: stale
          ? CapabilityAvailability.stale
          : CapabilityAvailability.available,
      value: distance.distanceMeters,
      observedAt: fix.observedAt,
      updatedAt: at,
      source: 'location.distance.haversine',
      platform: gateway.platformName,
    );
  }

  HomePresence _presence({
    required bool homeUsable,
    required HomeDistanceResult? distance,
    required LocationFix? fix,
    required bool stale,
  }) {
    if (_unsupported) return HomePresence.unsupported;
    if (!homeUsable) return HomePresence.unknown;
    if (fix == null) {
      // Unavailable or denied location must never be reported as "away".
      return HomePresence.unknown;
    }
    if (stale) return HomePresence.stale;
    return distance?.presence ?? HomePresence.unknown;
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<void> _restoreLastKnownFix() => _restoreTask ??= () async {
    if (_lastKnownFix != null) return;
    try {
      final stored = await store.readLastKnownFix();
      if (stored == null || _lastKnownFix != null) return;
      if (!stored.coordinate.isValid) return;
      // A restored fix keeps its real time; a future timestamp is discarded
      // rather than rewritten.
      if (stored.observedAt.toUtc().isAfter(now().toUtc())) return;
      _lastKnownFix = stored;
    } catch (_) {
      // Storage is optional; the location simply starts without history.
    }
  }();

  Future<void> _persistLastKnownFix(LocationFix fix) async {
    try {
      await store.writeLastKnownFix(fix);
    } catch (_) {
      // Persistence failure must not invalidate a successful observation.
    }
  }
}
