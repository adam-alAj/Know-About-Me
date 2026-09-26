import 'package:flutter/material.dart';

import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../domain/models/sharing_category.dart';

/// Informational privacy screen.
///
/// Phase 2 documents the category-level sharing model and lists the categories
/// from the domain enum, so UI and data model cannot drift apart. Interactive
/// toggles, pause and revoke controls are implemented in the privacy phase
/// (SRS FR-052 – FR-055).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Privacy and sharing',
      body: ListView(
        children: [
          const Text(
            'You choose which categories are shared with your connected '
            'partner. Each category can be paused independently; pausing '
            'location does not disconnect the relationship.',
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              children: [
                for (final category in SharingCategory.values)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(_labelFor(category)),
                    subtitle: const Text('Not configured yet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _labelFor(SharingCategory category) {
    switch (category) {
      case SharingCategory.battery:
        return 'Battery';
      case SharingCategory.charging:
        return 'Charging';
      case SharingCategory.network:
        return 'Network';
      case SharingCategory.location:
        return 'Location';
      case SharingCategory.distanceFromHome:
        return 'Distance from home';
      case SharingCategory.activityIndicators:
        return 'Activity indicators';
      case SharingCategory.ruleInterpretations:
        return 'Rule interpretations';
    }
  }
}
