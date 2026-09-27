import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../../location/domain/models/location_state.dart';
import '../../domain/models/device_location_state.dart';
import '../../domain/models/state_observation.dart';
import '../providers/device_state_providers.dart';

/// Minimal developer/debug rendering of Phase 10 location state.
///
/// Every line is a raw technical observation. Current and last-known location
/// are labelled separately, stale and unknown are spelled out, and distance is
/// always shown together with the fix's accuracy. Raw coordinates appear only
/// in debug builds: they are sensitive data and are not needed in a release UI.
class LocationSummaryCard extends ConsumerWidget {
  const LocationSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc();
    final locationAsync = ref.watch(currentLocalLocationStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Location (technical observations)'),
        const SizedBox(height: AppSpacing.xs),
        locationAsync.when(
          data: (state) => _LocationDetails(state: state, now: now),
          loading: () => const Text('Reading location state...'),
          error: (_, _) => const Text('Location state temporarily unavailable.'),
        ),
      ],
    );
  }
}

class _LocationDetails extends ConsumerWidget {
  const _LocationDetails({required this.state, required this.now});

  final DeviceLocationState state;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = state.location;
    final fix = location.value;
    final lastKnown = state.lastKnownLocation.value;
    final distance = state.distanceFromHome;
    final permission = state.permission.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Current location: ${_availabilityLabel(location.availability)}'),
        Text('Permission: ${_permissionLabel(permission)}'),
        Text('Location service: ${_serviceLabel(state.serviceState)}'),
        if (fix != null) ...[
          Text('Accuracy: ${_accuracyLabel(fix)}'),
          Text('Observed: ${_relativeTime(now, fix.observedAt)}'),
        ],
        Text('Freshness: ${_freshnessLabel(state.freshnessAt(now))}'),
        if (fix != null && kDebugMode)
          Text(
            'Coordinates: ${fix.coordinate.latitude.toStringAsFixed(4)}, '
            '${fix.coordinate.longitude.toStringAsFixed(4)}',
          ),
        Text(
          'Last known location: '
          '${lastKnown == null ? _availabilityLabel(state.lastKnownLocation.availability) : 'observed ${_relativeTime(now, lastKnown.observedAt)}'}',
        ),
        Text('Home location: ${_homeLabel(state)}'),
        Text('Distance from home: ${_distanceLabel(distance, state, now)}'),
        Text('At home: ${_presenceLabel(state.presence)}'),
        if (permission == DevicePermissionState.notDetermined ||
            permission == DevicePermissionState.denied) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Location is used only while this app is open, to compare with the '
            'home location you set yourself. It is never shared until you '
            'allow that separately, and never tracked in the background.',
          ),
          AppPermissionButton(
            onPressed: () =>
                ref.read(locationStateCollectorProvider).requestPermission(),
          ),
        ],
        if (permission == DevicePermissionState.permanentlyDenied ||
            permission == DevicePermissionState.restricted) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Location permission is blocked by the operating system. It will '
            'not be requested again; enable it in system settings to use '
            'distance from home.',
          ),
        ],
      ],
    );
  }

  static String _availabilityLabel(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => 'AVAILABLE',
        CapabilityAvailability.stale => 'STALE — not a current position',
        CapabilityAvailability.unavailable => 'UNAVAILABLE',
        CapabilityAvailability.unknown => 'UNKNOWN',
        CapabilityAvailability.unsupported => 'UNSUPPORTED',
        CapabilityAvailability.permissionDenied => 'PERMISSION NOT GRANTED',
        CapabilityAvailability.serviceDisabled => 'SERVICE DISABLED',
        CapabilityAvailability.error => 'TEMPORARILY UNAVAILABLE',
      };

  static String _permissionLabel(DevicePermissionState? permission) =>
      switch (permission) {
        DevicePermissionState.granted => 'Granted',
        DevicePermissionState.denied => 'Denied',
        DevicePermissionState.permanentlyDenied => 'Permanently denied',
        DevicePermissionState.restricted => 'Restricted by the OS',
        DevicePermissionState.limited => 'Limited (reduced accuracy)',
        DevicePermissionState.notDetermined => 'Not requested yet',
        DevicePermissionState.unknown => 'Unknown',
        DevicePermissionState.notApplicable => 'Not applicable',
        null => 'Unknown',
      };

  static String _serviceLabel(LocationServiceState service) => switch (service) {
    LocationServiceState.enabled => 'On',
    LocationServiceState.disabled => 'Off',
    LocationServiceState.unknown => 'Unknown',
  };

  static String _accuracyLabel(LocationFix fix) {
    final accuracy = fix.accuracyMeters;
    final rounded = accuracy?.round();
    if (rounded == null) {
      return fix.approximate
          ? 'Approximate — platform did not report a value'
          : 'Not reported by the platform';
    }
    return fix.approximate
        ? 'Approximate (±${rounded}m)'
        : '±${rounded}m';
  }

  static String _homeLabel(DeviceLocationState state) {
    if (!state.homeConfigured) return 'Not configured';
    if (!state.homeEnabled) return 'Configured but switched off';
    final radius = state.homeRadiusMeters;
    return radius == null
        ? 'Configured'
        : 'Configured (radius ${radius.round()}m)';
  }

  static String _distanceLabel(
    StateObservation<double> distance,
    DeviceLocationState state,
    DateTime now,
  ) {
    if (distance.availability == CapabilityAvailability.unsupported) {
      return 'Unsupported';
    }
    if (!state.homeConfigured) return 'No home location configured';
    if (!state.homeEnabled) return 'Home location is switched off';
    final value = distance.value;
    final accuracy = state.lastKnownLocation.value?.accuracyMeters;
    if (value == null) return _availabilityLabel(distance.availability);
    final metres = value.round();
    final uncertainty = accuracy == null ? '' : ' (±${accuracy.round()}m)';
    final marker = distance.availability == CapabilityAvailability.stale
        ? ' — from a stale fix'
        : '';
    final age = distance.observedAt == null
        ? ''
        : ' (fixed ${_relativeTime(now, distance.observedAt!)})';
    return '${metres}m$uncertainty$age$marker';
  }

  static String _presenceLabel(HomePresence presence) => switch (presence) {
    HomePresence.atHome => 'YES',
    HomePresence.awayFromHome => 'NO',
    HomePresence.nearHome => 'NEAR (not used by this phase)',
    HomePresence.stale => 'STALE — location too old to classify',
    HomePresence.unsupported => 'UNSUPPORTED',
    HomePresence.unknown => 'UNKNOWN — not enough information',
  };

  static String _freshnessLabel(DataFreshness freshness) => switch (freshness) {
    DataFreshness.fresh => 'Fresh',
    DataFreshness.recent => 'Recent',
    DataFreshness.stale => 'Stale',
    DataFreshness.unknown => 'Unknown',
  };

  static String _relativeTime(DateTime now, DateTime timestamp) {
    final age = now.toUtc().difference(timestamp.toUtc());
    if (age.isNegative || age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

/// Explicit user action for the OS prompt — location is never requested
/// automatically (Phase 10 §37).
class AppPermissionButton extends StatelessWidget {
  const AppPermissionButton({required this.onPressed, super.key});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onPressed(),
      child: const Text('Allow location access'),
    );
  }
}
