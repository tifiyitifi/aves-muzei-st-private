import 'package:aves/services/common/services.dart';

enum AlbumContentsMoveError {
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
/// the move, so a folder that still holds an invisible item or a subfolder is
/// kept.
class AlbumContentsMovePlan {
  /// The album the contents travel to.
  final String? destination;

  /// Visible entries that travel: those of the source albums other than the
  /// destination.
  final int entryCount;

  /// Source albums whose contents travel: the selection minus the destination.
  final Set<String> movingAlbums;

  final AlbumContentsMoveError? error;

  const new _({
    required this.destination,
    required this.entryCount,
    required this.movingAlbums,
    required this.error,
  });

  /// Plans the move of [entryCount] entries, which the caller counted over the
  /// source albums other than the destination.
  factory resolve({
    required Set<String> sourceAlbums,
    required String? destination,
    required int entryCount,
  }) {
    if (sourceAlbums.isEmpty) {
      return const AlbumContentsMovePlan._invalid(AlbumContentsMoveError.noAlbums);
    }

    final target = destination;
    if (target == null || target.isEmpty) {
      return const AlbumContentsMovePlan._invalid(AlbumContentsMoveError.destinationMissing);
    }

    if (sourceAlbums.any((album) => pContext.isWithin(album, target))) {
      return const AlbumContentsMovePlan._invalid(AlbumContentsMoveError.destinationInsideSource);
    }

    // Picking one of the selected albums merges the others into it.
    final movingAlbums = sourceAlbums.where((album) => album != target).toSet();
    if (movingAlbums.isEmpty) {
      return const AlbumContentsMovePlan._invalid(AlbumContentsMoveError.destinationIsOnlySource);
    }

    if (entryCount <= 0) {
      return const AlbumContentsMovePlan._invalid(AlbumContentsMoveError.noEntries);
    }

    return AlbumContentsMovePlan._(
      destination: target,
      entryCount: entryCount,
      movingAlbums: movingAlbums,
      error: null,
    );
  }

  const new _invalid(AlbumContentsMoveError error)
      : this._(
          destination: null,
          entryCount: 0,
          movingAlbums: const {},
          error: error,
        );

  bool get isValid => error == null;

  /// The selected albums this move may remove once it emptied them.
  ///
  /// [movedSourceAlbums] is what the move itself touched, so an album the
  /// selection held but this move never took anything from stays: only a folder
  /// this move emptied is eligible.
  Set<String> cleanupCandidates({
    required Set<String> movedSourceAlbums,
    required Set<String> removableSourceAlbums,
  }) {
    if (!isValid) return const {};
    return removableSourceAlbums.where((album) => album != destination && movedSourceAlbums.contains(album)).toSet();
  }
}
