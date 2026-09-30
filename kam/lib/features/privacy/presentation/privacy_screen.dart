import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/providers/profile_controller.dart';
import '../../device_state/domain/models/pair_sharing_state.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../../device_state/presentation/providers/sync_providers.dart';
import '../../location/domain/models/location_state.dart';
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
    final sharingConfirmed = sharingAsync.hasValue && !sharingAsync.hasError;
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
                  if (sharingAsync.isLoading && !sharingAsync.hasValue)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (!sharingConfirmed)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Settings are read-only until your current sharing choices can be confirmed.',
                      ),
                    ),
                  if (sharingAsync.hasError)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Sharing settings could not be confirmed. Try again when your connection is available.',
                      ),
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
                    onChanged: _busy || !sharingConfirmed
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
                      onChanged: _busy || !sharingConfirmed
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
          const SizedBox(height: 12),
          // Private to this device and available whether or not a partner is
          // connected: it is a reference point for the owner's own at-home
          // calculation, never a value the partner can read.
          const _HomeLocationCard(),
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
      return 'Not shared';
    }
    return switch (category) {
      SharingCategory.battery => 'Shared with your partner.',
      SharingCategory.charging => 'Charging state is shared.',
      SharingCategory.network => 'Network status is shared.',
      SharingCategory.location => 'Current or last known location is shared.',
      SharingCategory.distanceFromHome =>
        'At-home / away is shared. Your home coordinates stay private.',
      SharingCategory.activityIndicators => 'Screen and activity are shared.',
      SharingCategory.ruleInterpretations => 'Interpretations are shared.',
    };
  }
}

/// Sets, updates or removes the user's private home location (FR-022).
///
/// The home coordinate is captured from a current device fix and stored in the
/// owner-only preferences document. It is never published: only the derived
/// distance and at-home/away status travel to the partner, and only when the
/// user shares that category. With no home configured, the at-home status stays
/// `unknown` rather than being guessed.
class _HomeLocationCard extends ConsumerStatefulWidget {
  const _HomeLocationCard();

  @override
  ConsumerState<_HomeLocationCard> createState() => _HomeLocationCardState();
}

class _HomeLocationCardState extends ConsumerState<_HomeLocationCard> {
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    final locationState = ref.read(currentLocalLocationStateProvider).value;
    final fix =
        locationState?.lastKnownLocation.value ?? locationState?.location.value;
    if (fix == null) {
      _message(
        'A current location is needed to set your home. Allow location access '
        'and try again once this device has a fix.',
      );
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(profileControllerProvider.notifier)
        .setHomeLocation(
          HomeLocation(coordinate: fix.coordinate, label: 'Home'),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    _message(
      result.isSuccess
          ? 'Home location saved on this device.'
          : 'Your home location could not be saved. Try again.',
    );
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(profileControllerProvider.notifier)
        .setHomeLocation(null);
    if (!mounted) return;
    setState(() => _busy = false);
    _message(
      result.isSuccess
          ? 'Home location removed.'
          : 'Your home location could not be removed. Try again.',
    );
  }

  /// Opens the map picker, where the home point is chosen directly instead of
  /// being taken from wherever this device happens to be.
  Future<void> _identifyOnMap() async {
    if (_busy) return;
    await context.pushNamed(AppRoutes.homeLocationMap);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(currentUserPreferencesProvider).value
        ?.valueOrNull;
    final home = preferences?.homeLocation;
    final status = home == null
        ? 'Not configured'
        : home.enabled
        ? 'Configured (radius ${(home.radiusKm * 1000).round()} m)'
        : 'Configured but switched off';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Home location',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Status: $status'),
          const SizedBox(height: 8),
          const Text(
            'Home is a private reference point used only on this device to work '
            'out whether you are at home. Your exact home coordinates are never '
            'shared with your partner — only the derived at-home / away status '
            'you choose to share.',
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Identify home on map',
            icon: Icons.map_outlined,
            onPressed: _busy ? null : _identifyOnMap,
          ),
          const SizedBox(height: 8),
          AppButton.secondary(
            label: home == null
                ? 'Use current location'
                : 'Update from current location',
            icon: Icons.my_location,
            onPressed: _busy ? null : _save,
          ),
          if (home != null)
            TextButton(
              onPressed: _busy ? null : _remove,
              child: const Text('Remove home location'),
            ),
        ],
      ),
    );
  }
}
