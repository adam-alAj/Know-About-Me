import '../models/remote_device_state.dart';

/// Reads the authorized partner's synchronized device state.
///
/// This is the only path by which partner data enters the application, and it is
/// deliberately separate from [DeviceStateRepository]: remote state is never
/// merged into local state, and [PartnerDeviceState] cannot be passed where a
/// local snapshot is expected (Phase 11 §5).
abstract interface class PartnerDeviceStateRepository {
  /// Watches the partner's state for one active pair.
  ///
  /// Emits `null` after both initial documents are confirmed absent, otherwise
  /// emits as soon as any part of the partner state is known and on every
  /// change of either the state document or the location document. Callers must
  /// dispose the subscription when the pair ends, the user signs out, or the
  /// account changes — one active listener per authorized partner
  /// (Phase 11 §20, §21).
  Stream<PartnerDeviceState?> watch({
    required String pairId,
    required String partnerUserId,
  });
}
