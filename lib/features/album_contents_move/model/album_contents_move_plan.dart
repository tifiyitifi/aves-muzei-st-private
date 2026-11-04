import 'package:aves/model/entry/entry.dart';
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
/// Resolution is pure: it decides which visible entries travel, whether the
/// destination is usable, and which source albums are eligible for the
/// post-move empty-folder check. It never promises that a folder is empty:
/// emptiness is checked on the filesystem after the move, so a folder that
/// still holds an invisible item or a subfolder is kept.
class AlbumContentsMovePlan {
  final Map<String, Set<AvesEntry>> entriesByDestination;

  /// Selected source albums that had visible entries moved and may be removed
  /// if they are completely empty after the move.
  final Set<String> sourceAlbumsToClean;

  /// Source albums that actually lost at least one visible entry.
  final Set<String> movedSourceAlbums;

  final AlbumContentsMoveError? error;

  const new _({
    required this.entriesByDestination,
    required this.sourceAlbumsToClean,
    required this.movedSourceAlbums,
    required this.error,
  });

  factory resolve({
    required Set<String> sourceAlbums,
    required Set<String> removableSourceAlbums,
    required String? destination,
    required Iterable<AvesEntry> entries,
  }) {
    if (sourceAlbums.isEmpty) {
      return const AlbumContentsMovePlan._(
        entriesByDestination: {},
        sourceAlbumsToClean: {},
        movedSourceAlbums: {},
        error: AlbumContentsMoveError.noAlbums,
      );
    }

    final target = destination;
    if (target == null || target.isEmpty) {
      return const AlbumContentsMovePlan._(
        entriesByDestination: {},
        sourceAlbumsToClean: {},
        movedSourceAlbums: {},
        error: AlbumContentsMoveError.destinationMissing,
      );
    }

    if (sourceAlbums.any((album) => pContext.isWithin(album, target))) {
      return const AlbumContentsMovePlan._(
        entriesByDestination: {},
        sourceAlbumsToClean: {},
        movedSourceAlbums: {},
        error: AlbumContentsMoveError.destinationInsideSource,
      );
    }

    // Picking one of the selected albums merges the others into it.
    final movingAlbums = sourceAlbums.where((album) => album != target).toSet();
    if (movingAlbums.isEmpty) {
      return const AlbumContentsMovePlan._(
        entriesByDestination: {},
        sourceAlbumsToClean: {},
        movedSourceAlbums: {},
        error: AlbumContentsMoveError.destinationIsOnlySource,
      );
    }

    final moved = entries.where((entry) {
      final directory = entry.directory;
      return directory != null && movingAlbums.contains(directory);
    }).toSet();

    if (moved.isEmpty) {
      return const AlbumContentsMovePlan._(
        entriesByDestination: {},
        sourceAlbumsToClean: {},
        movedSourceAlbums: {},
        error: AlbumContentsMoveError.noEntries,
      );
    }

    final movedSourceAlbums = moved.map((entry) => entry.directory).whereType<String>().toSet();
    final cleanup = removableSourceAlbums.where((album) => album != target && movedSourceAlbums.contains(album)).toSet();

    return AlbumContentsMovePlan._(
      entriesByDestination: {target: moved},
      sourceAlbumsToClean: cleanup,
      movedSourceAlbums: movedSourceAlbums,
      error: null,
    );
  }

  bool get isValid => error == null;

  int get entryCount => entriesByDestination.values.fold(0, (sum, entries) => sum + entries.length);
}
