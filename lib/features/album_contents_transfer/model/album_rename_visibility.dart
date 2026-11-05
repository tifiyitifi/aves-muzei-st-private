/// What a rename can know about the folder behind an album.
///
/// A rename renames the folder, so it moves everything inside; the album tile
/// and every entry action count what the view shows. Comparing the two is what
/// tells an action whether those are the same set.
class AlbumRenameVisibility {
  /// Rows the current view shows for the album, i.e. the tile's count.
  final int visible;

  /// Rows the folder holds, whatever the view filters out.
  final int total;

  const new({required this.visible, required this.total});

  /// Rows the folder holds but the view does not show: a visible range, a
  /// hidden filter, or the trash.
  int get unseen => total > visible ? total - visible : 0;

  /// Whether a whole-folder rename moves exactly what the user sees.
  bool get coversAlbum => unseen == 0;
}
