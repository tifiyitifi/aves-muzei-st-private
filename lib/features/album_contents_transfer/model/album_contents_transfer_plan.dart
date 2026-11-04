import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

enum AlbumContentsTransferError {
  noAlbums,
  noEntries,
  destinationMissing,
  destinationInsideSource,
  destinationIsOnlySource,
}

/// The outcome of pointing the selected albums at a destination.
///
/// Resolution is pure: it validates the destination and reports how many visible
/// entries travel, from counts rather than from the entries themselves, so a
/// windowed collection can plan without materializing its rows. It never
/// promises that a folder is empty: emptiness is checked on the filesystem after
/// the transfer, so a folder that still holds an invisible item or a subfolder is
/// kept.
///
/// A copy plans like a move, except that it leaves every source album in place,
/// so it never offers a folder for removal.
class AlbumContentsTransferPlan {
  /// Whether the contents are moved or duplicated.
  final MoveType moveType;

  /// The album the contents travel to.
  final String? destination;

  /// Visible entries that travel: those of the source albums other than the
  /// destination.
  final int entryCount;

  /// Source albums whose contents travel: the selection minus the destination.
  final Set<String> movingAlbums;

  final AlbumContentsTransferError? error;

  const new _({
    required this.moveType,
    required this.destination,
    required this.entryCount,
    required this.movingAlbums,
    required this.error,
  });

  /// Plans the transfer of [entryCount] entries, which the caller counted over
  /// the source albums other than the destination.
  factory resolve({
    required MoveType moveType,
    required Set<String> sourceAlbums,
    required String? destination,
    required int entryCount,
  }) {
    if (sourceAlbums.isEmpty) {
      return AlbumContentsTransferPlan._invalid(moveType, AlbumContentsTransferError.noAlbums);
    }

    final target = destination;
    if (target == null || target.isEmpty) {
      return AlbumContentsTransferPlan._invalid(moveType, AlbumContentsTransferError.destinationMissing);
    }

    if (sourceAlbums.any((album) => pContext.isWithin(album, target))) {
      return AlbumContentsTransferPlan._invalid(moveType, AlbumContentsTransferError.destinationInsideSource);
    }

    // Picking one of the selected albums merges the others into it.
    final movingAlbums = sourceAlbums.where((album) => album != target).toSet();
    if (movingAlbums.isEmpty) {
      return AlbumContentsTransferPlan._invalid(moveType, AlbumContentsTransferError.destinationIsOnlySource);
    }

    if (entryCount <= 0) {
      return AlbumContentsTransferPlan._invalid(moveType, AlbumContentsTransferError.noEntries);
    }

    return AlbumContentsTransferPlan._(
      moveType: moveType,
      destination: target,
      entryCount: entryCount,
      movingAlbums: movingAlbums,
      error: null,
    );
  }

  const new _invalid(this.moveType, this.error)
      : destination = null,
        entryCount = 0,
        movingAlbums = const {};

  bool get isValid => error == null;

  /// Whether the plan duplicates the contents instead of moving them.
  bool get copies => moveType == MoveType.copy;

  /// The selected albums this move may remove once it emptied them.
  ///
  /// [movedSourceAlbums] is what the move itself touched, so an album the
  /// selection held but this move never took anything from stays: only a folder
  /// this move emptied is eligible. A copy empties nothing, so it offers no
  /// candidate at all.
  Set<String> cleanupCandidates({
    required Set<String> movedSourceAlbums,
    required Set<String> removableSourceAlbums,
  }) {
    if (!isValid || copies) return const {};
    return removableSourceAlbums.where((album) => album != destination && movedSourceAlbums.contains(album)).toSet();
  }
}
