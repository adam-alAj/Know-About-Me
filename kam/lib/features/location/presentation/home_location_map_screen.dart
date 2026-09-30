import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/ui/widgets/app_button.dart';
import '../../../core/ui/widgets/app_card.dart';
import '../../../core/ui/widgets/app_scaffold.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/providers/profile_controller.dart';
import '../../device_state/presentation/providers/device_state_providers.dart';
import '../domain/models/location_state.dart';

/// Identifies the user's private home on a map (SRS FR-022).
///
/// The map opens at the already-configured home, or failing that at this
/// device's own fix, and the pin fixed at the centre of the map marks the chosen
/// point. Only the chosen coordinate is stored, and only in the owner-only
/// preferences document: the partner never receives it, only the derived
/// distance and at-home / away status they are allowed to see.
///
/// The map is a deliberate user action, not an observation: this screen never
/// records a trail, never polls and never infers a home from movement.
class HomeLocationMapScreen extends ConsumerStatefulWidget {
  const HomeLocationMapScreen({super.key});

  @override
  ConsumerState<HomeLocationMapScreen> createState() =>
      _HomeLocationMapScreenState();
}

class _HomeLocationMapScreenState extends ConsumerState<HomeLocationMapScreen> {
  /// Close enough to a street to place a pin; the user can zoom further.
  static const double _centreZoom = 16;

  /// Used only when neither a configured home nor any fix is available, so the
  /// user can still pan to their home instead of meeting a dead end.
  static const double _worldZoom = 2;
  static final LatLng _worldCentre = LatLng(20, 0);

  final MapController _controller = MapController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The point currently under the centre pin, or `null` before the map is
  /// attached. Reading it at confirm time avoids a callback that would rebuild
  /// the screen on every pan.
  LatLng? _pinnedCentre() {
    try {
      return _controller.camera.center;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final centre = _pinnedCentre();
    if (centre == null) {
      _message('The map is still loading. Try again in a moment.');
      return;
    }
    final coordinate = Coordinate(
      latitude: centre.latitude,
      longitude: centre.longitude,
    );
    if (!coordinate.isValid) {
      _message('That point is not a valid location. Move the map and try again.');
      return;
    }
    final existing = ref
        .read(currentUserPreferencesProvider)
        .value
        ?.valueOrNull
        ?.homeLocation;
    setState(() => _busy = true);
    final result = await ref
        .read(profileControllerProvider.notifier)
        // An existing home keeps its label, radius and enabled switch; only the
        // point the user just chose changes.
        .setHomeLocation(
          existing == null
              ? HomeLocation(coordinate: coordinate, label: 'Home')
              : existing.copyWith(coordinate: coordinate),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      _message('Home location saved on this device.');
      Navigator.of(context).pop();
      return;
    }
    _message('Your home location could not be saved. Try again.');
  }

  Future<void> _centreOnCurrentLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Read the platform once, through the same collector the rest of the app
      // uses. A missing permission or a switched-off service yields no fix, and
      // the user is told so rather than being shown an invented position.
      final state = await ref.read(locationStateCollectorProvider).refresh();
      final fix =
          state.location.value?.coordinate ??
          state.lastKnownLocation.value?.coordinate;
      if (!mounted) return;
      if (fix == null) {
        _message(
          'No location is available yet. Check that location access is on, '
          'then try again.',
        );
        return;
      }
      _controller.move(LatLng(fix.latitude, fix.longitude), _centreZoom);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref
        .watch(currentUserPreferencesProvider)
        .value
        ?.valueOrNull;
    final locationAsync = ref.watch(currentLocalLocationStateProvider);
    final home = preferences?.homeLocation;

    // A configured home is authoritative and immediately available; only when
    // there is none do we wait for this device's own first reading, so the map
    // does not open at a wide view and then jump.
    if (home == null && locationAsync.isLoading) {
      return const AppScaffold(
        title: 'Identify home',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final fix =
        locationAsync.value?.location.value?.coordinate ??
        locationAsync.value?.lastKnownLocation.value?.coordinate;
    final anchor = home?.coordinate ?? fix;
    final hasPosition = anchor != null;
    final centre = anchor == null
        ? _worldCentre
        : LatLng(anchor.latitude, anchor.longitude);

    return AppScaffold(
      title: 'Identify home',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mapHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight * 0.55).clamp(240.0, 520.0)
              : 360.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Drag the map so the pin sits on your home, then save.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: mapHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                  child: Stack(
                    children: [
                      _map(centre, hasPosition: hasPosition),
                      // The pin is decoration over the map: it never absorbs a
                      // gesture, so panning under it keeps working.
                      IgnorePointer(
                        child: Center(
                          child: Transform.translate(
                            // The pin's tip, not its middle, must mark the point.
                            offset: const Offset(0, -22),
                            child: Icon(
                              Icons.location_pin,
                              size: 44,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        right: 6,
                        bottom: 4,
                        child: _MapAttribution(),
                      ),
                    ],
                  ),
                ),
              ),
              if (!hasPosition) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This device has no location right now, so the map opened at '
                  'a wide view. Pan to your home, or use your current location.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: _busy ? 'Saving…' : 'Save this as my home',
                icon: Icons.home_outlined,
                onPressed: _busy ? null : _save,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton.secondary(
                label: 'Use my current location',
                icon: Icons.my_location,
                onPressed: _busy ? null : _centreOnCurrentLocation,
              ),
              const SizedBox(height: AppSpacing.md),
              const AppCard(
                child: Text(
                  'Your home stays private. Only the point you save here is '
                  'stored, on your own account, and your exact home '
                  'coordinates are never shared with your partner — only the '
                  'derived at-home / away status you choose to share.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _map(LatLng centre, {required bool hasPosition}) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: hasPosition ? _centreZoom : _worldZoom,
        // Panning is the whole interaction: the centre pin reads the position.
        keepAlive: true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.aj.kam',
          maxZoom: 19,
        ),
      ],
    );
  }
}

/// OpenStreetMap attribution, required by the tile usage policy.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
