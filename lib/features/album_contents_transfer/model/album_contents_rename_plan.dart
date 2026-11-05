import 'package:aves/services/common/services.dart';

enum AlbumContentsRenameError {
  noAlbum,
  emptyName,
  sameName,
}

/// How a stored album's rename maps onto the filesystem.
///
/// A rename is a move of the album's contents into a sibling folder, so
/// resolution only derives and validates that destination: the caller can plan
/// without holding the entries. An existing destination is merged into, exactly
/// as the legacy move allows, so no emptiness check is made here.
class AlbumContentsRenamePlan {
  /// The album being renamed.
  final String album;

  /// The sibling folder its contents move to.
  final String destination;

  final AlbumContentsRenameError? error;

  const new _({
    required this.album,
    required this.destination,
    required this.error,
  });

  factory resolve({required String album, required String newName}) {
    if (album.isEmpty) {
      return AlbumContentsRenamePlan._(album: album, destination: '', error: AlbumContentsRenameError.noAlbum);
    }
    final parent = pContext.dirname(album);
    if (newName.isEmpty) {
      return AlbumContentsRenamePlan._(album: album, destination: parent, error: AlbumContentsRenameError.emptyName);
    }

    final destination = pContext.join(parent, newName);
    if (destination == album) {
      return AlbumContentsRenamePlan._(album: album, destination: destination, error: AlbumContentsRenameError.sameName);
    }
    return AlbumContentsRenamePlan._(album: album, destination: destination, error: null);
  }

  bool get isValid => error == null;

  /// Whether the new name resolves to the album itself: there is nothing to
  /// move, so the caller can answer success without touching anything.
  bool get isNoOp => error == AlbumContentsRenameError.sameName;

  /// Only the case differs. A case-insensitive lookup would resolve the new
  /// name to the album itself and turn a direct rename into a silent no-op, so
  /// the rename strategies go through a temporary name for this case.
  bool get isCaseOnly => album != destination && album.toLowerCase() == destination.toLowerCase();
}
