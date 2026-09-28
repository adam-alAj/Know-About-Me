import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../device_state/domain/models/pair_sharing_state.dart';
import '../../device_state/presentation/providers/sync_providers.dart';
import '../../pairing/domain/models/pair_membership.dart';
import '../../pairing/presentation/providers/pairing_providers.dart';
import '../domain/models/sharing_category.dart';

/// Privacy controls for the authenticated user's current two-person connection.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;

  Future<void> _setSharing({
    bool? paused,
    Set<SharingCategory>? categories,
  }) async {
    final scope = ref.read(partnerScopeProvider).value;
    final uid = ref.read(currentIdentityProvider)?.uid;
    final repository = ref.read(sharingRepositoryProvider);
    if (scope == null || uid == null || repository == null || _busy) return;
    final current =
        ref.read(ownSharingProvider).asData?.value ?? PairSharingState.none;
    setState(() => _busy = true);
    try {
      await repository.setSharing(
        pairId: scope.pairId,
        userId: uid,
        paused: paused ?? current.paused,
        categories: categories ?? current.categories,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save this setting. It will remain off until confirmed.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endConnection({required bool revoke}) async {
    final scope = ref.read(partnerScopeProvider).value;
    final repository = ref.read(pairingRepositoryProvider);
    if (scope == null || repository == null || _busy) return;
    final action = revoke ? 'Revoke' : 'Disconnect';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action connection?'),
        content: Text(
          revoke
              ? 'This permanently revokes sharing for this connection. You will need to create a new connection to share again.'
              : 'This ends the connection. Your partner will no longer be able to access new live data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (approved != true) return;
    setState(() => _busy = true);
    try {
      if (revoke) {
        await repository.revoke(scope.pairId);
      } else {
        await repository.disconnect(scope.pairId);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update the connection. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scopeAsync = ref.watch(partnerScopeProvider);
    final scope = scopeAsync.value;
    final nameAsync = ref.watch(partnerDisplayNameProvider);
    final sharingAsync = ref.watch(ownSharingProvider);
    final memberships = ref.watch(pairMembershipsProvider).value ?? const [];
    final sharing = sharingAsync.asData?.value ?? PairSharingState.none;
    final matchingMemberships = scope == null
        ? const <PairMembership>[]
        : memberships.where((item) => item.pairId == scope.pairId).toList();
    final membership = matchingMemberships.isEmpty
        ? null
        : matchingMemberships.first;
    final partnerName = nameAsync.value ?? 'Your partner';

    return AppScaffold(
      title: 'Privacy and sharing',
      body: ListView(
        children: [
          const Text(
            'You choose what your partner can see. New connections share no device categories until you turn them on.',
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (scopeAsync.isLoading)
                  const Text('Checking connection…')
                else if (scope == null) ...[
                  const Text('No active connection. Nothing is shared.'),
                  for (final item in memberships.where((item) => item.isEnded))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Previous connection: ${item.status}'),
                    ),
                ] else ...[
                  Text(partnerName),
                  Text(
                    'Status: ${membership?.isFromCache == true ? 'Last confirmed ${membership!.status}' : membership?.status ?? 'active'}',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (scope != null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What you share',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      sharing.paused ? 'Sharing paused' : 'Pause all sharing',
                    ),
                    subtitle: const Text(
                      'Pausing temporarily stops live sharing. Your category choices are saved.',
                    ),
                    value: sharing.paused,
                    onChanged: _busy
                        ? null
                        : (value) => _setSharing(paused: value),
                  ),
                  const Divider(),
                  for (final category in SharingCategory.values)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_label(category)),
                      subtitle: Text(
                        _description(
                          category,
                          sharing.categories.contains(category),
                        ),
                      ),
                      value: sharing.categories.contains(category),
                      onChanged: _busy
                          ? null
                          : (value) {
                              final next = Set<SharingCategory>.of(
                                sharing.categories,
                              );
                              if (value) {
                                next.add(category);
                              } else {
                                next.remove(category);
                              }
                              _setSharing(categories: next);
                            },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection controls',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _endConnection(revoke: false),
                    child: const Text('Disconnect'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _endConnection(revoke: true),
                    child: const Text('Revoke connection'),
                  ),
                ],
              ),
            ),
          ],
          if (sharingAsync.hasError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sharing settings could not be confirmed. Sharing is treated as off until they can be read.',
              ),
            ),
        ],
      ),
    );
  }

  static String _label(SharingCategory category) => switch (category) {
    SharingCategory.battery => 'Battery',
    SharingCategory.charging => 'Charging',
    SharingCategory.network => 'Network',
    SharingCategory.location => 'Location',
    SharingCategory.distanceFromHome => 'Home and distance',
    SharingCategory.activityIndicators => 'Activity and screen state',
    SharingCategory.ruleInterpretations => 'Rule interpretations',
  };

  static String _description(SharingCategory category, bool enabled) {
    if (!enabled) {
      return 'Not shared. Your partner cannot see this information.';
    }
    return switch (category) {
      SharingCategory.battery => 'Your battery percentage is shared.',
      SharingCategory.charging => 'Whether your device is charging is shared.',
      SharingCategory.network =>
        'Your observed network status is shared; missing connectivity does not mean the phone is off.',
      SharingCategory.location =>
        'Your current or last known location may be shared when the device permission and location service are available. Turn this off to remove location from your partner view.',
      SharingCategory.distanceFromHome =>
        'Derived home presence or approximate distance may be shared when Location is also enabled. Your exact home coordinates are not sent.',
      SharingCategory.activityIndicators =>
        'Your observed activity and screen state may be shared where the platform supports them.',
      SharingCategory.ruleInterpretations =>
        'Rule interpretation events may be shared with your partner.',
    };
  }
}
