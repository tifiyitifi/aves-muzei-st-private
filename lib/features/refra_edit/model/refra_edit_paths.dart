/// Where the copy-first editor stages its files, relative to the primary storage root.
///
/// Kept next to the feature so the staging layout has one owner: [RefraEditService] builds the
/// session paths from it and the album list groups the tree from it.
const String refraEditStagingRelativeRoot = 'Pictures/aves_refra_edit';

/// Whether [dirPath] lies inside the editor's staging tree.
///
/// The tree is this app's working area for copies it is about to edit, not a user album, so it is
/// grouped with the other app-owned directories instead of being counted as a normal photo folder.
bool isRefraEditStagingPath(String dirPath) {
  final normalized = dirPath.replaceAll(r'\', '/').toLowerCase();
  final root = refraEditStagingRelativeRoot.toLowerCase();
  return normalized.endsWith('/$root') || normalized.contains('/$root/');
}
