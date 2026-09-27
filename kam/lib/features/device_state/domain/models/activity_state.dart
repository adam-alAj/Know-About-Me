import '../../../../core/freshness/data_freshness.dart';
import 'state_observation.dart';

/// The technical state of the device display, observed only where the
/// operating system genuinely exposes it.
///
/// This is a fact about the display, never a claim about a person: `on` does
/// not mean anyone is looking at or touching the phone. Platforms that cannot
/// report a display state must report
/// [CapabilityAvailability.unsupported] instead of guessing.
enum DeviceScreenState {
  on,
  off,

  /// The platform API itself reported that the state is not determinable.
  unknown,
}

/// Whether a supported activity *signal* is currently active.
///
/// The signals are technical events only (for example a screen on/off
/// transition or this application returning to the foreground). The value is
/// never an interpretation of human behaviour: `activityDetected` must not be
/// read as "the person is using the phone".
enum ActivityStatus {
  activityDetected,
  noActivityObserved,
  unknown,
}

/// Lifecycle of **this application**, as reported by the Flutter framework.
///
/// Kept strictly separate from [DeviceScreenState]: an app in the background
/// tells nothing about the display or about the person, who may simply be
/// using a different application.
enum AppLifecyclePhase {
  foreground,
  background,
  inactive,
  hidden,
  detached,

  /// No lifecycle report has been received yet.
  unknown,
}

/// A point-in-time activity observation for this device.
///
/// Field semantics (SRS FR-016, FR-017):
///
/// * [lastObservedActivityAt] is the most recent time this application saw a
///   supported signal event. It is never "last time the person touched the
///   phone" unless the platform actually exposed that event, and it is never
///   fabricated by starting, refreshing or restarting the app.
/// * [activityStartedAt] exists only when a transition into the detected state
///   was observed within the current monitoring session. When the application
///   starts while a signal is already active, the start is unknown rather than
///   assumed to be the app start time.
/// * [screenState] is unsupported on platforms with no display-state API and
///   is never approximated.
class ActivityState {
  const ActivityState({
    required this.screenState,
    required this.activityStatus,
    required this.appLifecycle,
    required this.activityDuration,
    this.lastObservedActivityAt,
    this.activityStartedAt,
  });

  /// An "nothing has been observed" state used before any signal arrives.
  static const ActivityState unknown = ActivityState(
    screenState: StateObservation<DeviceScreenState>(
      availability: CapabilityAvailability.unknown,
    ),
    activityStatus: StateObservation<ActivityStatus>(
      availability: CapabilityAvailability.unknown,
      value: ActivityStatus.unknown,
    ),
    appLifecycle: StateObservation<AppLifecyclePhase>(
      availability: CapabilityAvailability.unknown,
    ),
    activityDuration: StateObservation<Duration>(
      availability: CapabilityAvailability.unknown,
    ),
  );

  /// Display state, or an explicit non-available reason.
  final StateObservation<DeviceScreenState> screenState;

  /// Derived status of the currently supported signals.
  final StateObservation<ActivityStatus> activityStatus;

  /// This application's own lifecycle, independent of the display.
  final StateObservation<AppLifecyclePhase> appLifecycle;

  /// Time since an observed transition into the detected state; unknown when
  /// the start was never observed, unavailable when no signal is detected.
  final StateObservation<Duration> activityDuration;

  /// Most recent observed signal event, `null` when none has been observed
  /// since installation. May be restored from local persistence after a
  /// restart; a restored value keeps its historical time.
  final DateTime? lastObservedActivityAt;

  /// When the current detected-state session began, `null` when unknown.
  final DateTime? activityStartedAt;

  /// Every component observation, used for availability derivation.
  Iterable<StateObservation<Object?>> get observations => [
    screenState,
    activityStatus,
    appLifecycle,
    activityDuration,
  ];

  /// Freshness of the snapshot at [now].
  ///
  /// The display observation is the primary signal where supported; otherwise
  /// the application lifecycle (a slower-changing fact) is used.
  DataFreshness freshnessAt(DateTime now) {
    if (screenState.availability == CapabilityAvailability.available) {
      return screenState.freshnessAt(now);
    }
    return appLifecycle.freshnessAt(now, FreshnessPolicy.slow);
  }

  Map<String, Object?> toJson() => {
    'screenState': screenState.toJson(encodeValue: (value) => value.name),
    'activityStatus': activityStatus.toJson(encodeValue: (value) => value.name),
    'appLifecycle': appLifecycle.toJson(encodeValue: (value) => value.name),
    'lastObservedActivityAt': lastObservedActivityAt
        ?.toUtc()
        .toIso8601String(),
    'activityStartedAt': activityStartedAt?.toUtc().toIso8601String(),
    'activityDuration': activityDuration.toJson(
      encodeValue: (value) => value.inMilliseconds,
    ),
  };

  factory ActivityState.fromJson(Map<String, Object?> json) => ActivityState(
    screenState: StateObservation<DeviceScreenState>.fromJson(
      Map<String, Object?>.from(json['screenState']! as Map),
      decodeValue: (value) => DeviceScreenState.values.byName(value! as String),
    ),
    activityStatus: StateObservation<ActivityStatus>.fromJson(
      Map<String, Object?>.from(json['activityStatus']! as Map),
      decodeValue: (value) => ActivityStatus.values.byName(value! as String),
    ),
    appLifecycle: StateObservation<AppLifecyclePhase>.fromJson(
      Map<String, Object?>.from(json['appLifecycle']! as Map),
      decodeValue: (value) => AppLifecyclePhase.values.byName(value! as String),
    ),
    lastObservedActivityAt: _date(json['lastObservedActivityAt']),
    activityStartedAt: _date(json['activityStartedAt']),
    activityDuration: StateObservation<Duration>.fromJson(
      Map<String, Object?>.from(json['activityDuration']! as Map),
      decodeValue: (value) => Duration(milliseconds: value! as int),
    ),
  );

  static DateTime? _date(Object? value) => value == null
      ? null
      : DateTime.parse(value as String).toUtc();
}
