import '../../../privacy/domain/models/sharing_category.dart';
import '../models/pair_sharing_state.dart';

/// Reads and writes one member's sharing switches for one pair.
///
/// The repository takes the pair and user ids as parameters, and its caller must
/// supply them from authenticated application state — never from a UI field —
/// so a modified client cannot point a write at someone else's document
/// (Phase 11 §22).
abstract interface class SharingRepository {
  /// Watches the owner's own sharing document.
  ///
  /// Emits [PairSharingState.none] while the document does not exist or is
  /// unreadable, so an unknown state is fail-closed rather than permissive.
  Stream<PairSharingState> watch({
    required String pairId,
    required String userId,
  });

  /// Replaces the owner's sharing switches.
  Future<void> setSharing({
    required String pairId,
    required String userId,
    required bool paused,
    required Set<SharingCategory> categories,
  });
}
