import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/section_card.dart';
import '../../../../core/ui/widgets/skeleton.dart';
import '../../../location/domain/models/location_state.dart';
import '../../domain/models/device_location_state.dart';
import '../../domain/models/state_observation.dart';
import '../providers/device_state_providers.dart';

/// This device's own location state, in the user's words.
///
/// Every value is an observation and is labelled as one: current and last-known
/// location are separated, stale and unknown are spelled out, and distance is
/// always shown together with the accuracy that limits it. Raw coordinates
/// appear only in debug builds — they are sensitive and are never needed in a
/// release UI, and they are never shared with the partner.
class LocationSummaryCard extends ConsumerWidget {
  const LocationSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc();
    final locationAsync = ref.watch(currentLocalLocationStateProvider);

    final state = locationAsync.value;
    if (state == null) {
      if (locationAsync.hasError) {
        return const SectionCard(
          title: 'Location',
          icon: Icons.location_on_outlined,
          rows: [
            StateRow(label: 'Status', value: 'Temporarily unavailable'),
          ],
        );
      }
      return const SectionSkeleton(
        title: 'Location',
        icon: Icons.location_on_outlined,
        rows: 4,
      );
    }

    return _LocationDetails(state: state, now: now);
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

    final needsPrompt =
        permission == DevicePermissionState.notDetermined ||
        permission == DevicePermissionState.denied;
    final blocked =
        permission == DevicePermissionState.permanentlyDenied ||
        permission == DevicePermissionState.restricted;

    return SectionCard(
      title: 'Location',
      icon: Icons.location_on_outlined,
      rows: [
        StateRow(
          label: 'Current',
          value: _availabilityLabel(location.availability),
          emphasis: StateRowEmphasis.strong,
        ),
        if (fix != null) ...[
          StateRow(label: 'Accuracy', value: _accuracyLabel(fix)),
          StateRow(
            label: 'Observed',
            value: _relativeTime(now, fix.observedAt),
          ),
        ],
        if (fix != null && kDebugMode)
          StateRow(
            label: 'Coordinates (debug)',
            value:
                '${fix.coordinate.latitude.toStringAsFixed(4)}, '
                '${fix.coordinate.longitude.toStringAsFixed(4)}',
          ),
        StateRow(
          label: 'Last known',
          value: lastKnown == null
              ? _availabilityLabel(state.lastKnownLocation.availability)
              : 'observed ${_relativeTime(now, lastKnown.observedAt)}',
        ),
        StateRow(label: 'Home', value: _homeLabel(state)),
        StateRow(
          label: 'Distance from home',
          value: _distanceLabel(distance, state, now),
        ),
        StateRow(label: 'At home', value: _presenceLabel(state.presence)),
        StateRow(label: 'Permission', value: _permissionLabel(permission)),
        StateRow(label: 'Location service', value: _serviceLabel(state.serviceState)),
      ],
      footer: needsPrompt
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location is used only while this app is open, to compare with '
                  'the home location you set yourself. It is never shared until '
                  'you allow that separately, and never tracked in the '
                  'background.',
                ),
                AppPermissionButton(
                  onPressed: () =>
                      ref.read(locationStateCollectorProvider).requestPermission(),
                ),
              ],
            )
          : blocked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location permission is blocked. Enable approximate or '
                  'precise location for Know About Me in Android app settings '
                  'to use distance from home.',
                ),
                TextButton(
                  onPressed: () => ref
                      .read(locationStateCollectorProvider)
                      .openAppSettings(),
                  child: const Text('Open app settings'),
                ),
              ],
            )
          : null,
    );
  }

  static String _availabilityLabel(CapabilityAvailability availability) =>
      switch (availability) {
        CapabilityAvailability.available => 'Available',
        CapabilityAvailability.stale => 'Stale',
        CapabilityAvailability.unavailable => 'Unavailable',
        CapabilityAvailability.unknown => 'Unknown',
        CapabilityAvailability.unsupported => 'Unsupported',
        CapabilityAvailability.permissionDenied => 'Permission required',
        CapabilityAvailability.serviceDisabled => 'Location off',
        CapabilityAvailability.error => 'Temporarily unavailable',
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
    return fix.approximate ? 'Approximate (±${rounded}m)' : '±${rounded}m';
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
    return '$metres m$uncertainty$marker';
  }

  static String _presenceLabel(HomePresence presence) => switch (presence) {
    HomePresence.atHome => 'At home',
    HomePresence.awayFromHome => 'Away',
    HomePresence.nearHome => 'Near home',
    HomePresence.stale => 'Stale',
    HomePresence.unsupported => 'Unsupported',
    HomePresence.unknown => 'Unknown',
  };

  static String _relativeTime(DateTime now, DateTime timestamp) {
    final age = now.toUtc().difference(timestamp.toUtc());
    if (age.isNegative || age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    if (age.inHours < 24) return '${age.inHours} h ago';
    return '${age.inDays} d ago';
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
