import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/freshness/data_freshness.dart';
import '../../../../core/ui/widgets/app_button.dart';
import '../../domain/models/remote_device_state.dart';
import '../providers/device_state_providers.dart';

/// The "open the partner's location in a map" action (FR-025).
///
/// It appears only when the partner has shared a usable coordinate — never for
/// an unavailable, unshared or malformed location — and it labels a stale fix
/// honestly as the *last known* location rather than presenting it as current.
/// The action itself never decides authorization: the coordinate it receives has
/// already passed the sharing gate and the Security Rules.
class PartnerLocationActions extends ConsumerWidget {
  const PartnerLocationActions({
    super.key,
    required this.location,
    required this.now,
  });

  final RemoteLocationState location;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!location.hasCoordinates) return const SizedBox.shrink();
    final stale = location.freshnessAt(now) == DataFreshness.stale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stale)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'This is the last known location, not a current position.',
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            label: stale ? 'Open last known location' : 'Open in Google Maps',
            icon: Icons.map_outlined,
            onPressed: () => _open(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final latitude = location.latitude;
    final longitude = location.longitude;
    if (latitude == null || longitude == null) return;
    final opened = await ref
        .read(mapLauncherProvider)
        .openCoordinates(latitude: latitude, longitude: longitude);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No map application is available to open this location.',
        ),
      ),
    );
  }
}
