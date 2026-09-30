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
  /// Emits `null` after the watched initial documents are confirmed absent,
  /// otherwise emits as soon as any part of the partner state is known and on
  /// every change of a watched document. Callers must dispose the subscription
  /// when the pair ends, the user signs out, or the account changes — one
  /// active listener per authorized partner (Phase 11 §20, §21).
  ///
  /// [watchDeviceState] and [watchLocation] say which documents the caller is
  /// authorized to read. Each document has its own read gate in the security
  /// rules, and reading a document whose category is not shared is denied. A
  /// denied read therefore must not be attempted at all: it must not take down
  /// the document the partner *did* share. A document that is not watched is
  /// reported as explicitly unavailable rather than fetched and denied.
  Stream<PartnerDeviceState?> watch({
    required String pairId,
    required String partnerUserId,
    bool watchDeviceState = true,
    bool watchLocation = true,
  });
}
