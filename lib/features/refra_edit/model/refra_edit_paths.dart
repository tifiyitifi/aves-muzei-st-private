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

final _contentMediaIdPattern = RegExp(r'/(?:media|file)/(\d+)$');

/// Identity of a file inside the staging tree, independent of how a row names its volume.
///
/// The media operation reports the primary volume as `external_primary` while the scanner reports
/// `external`, and the legacy `files` collection adds yet another alias; all of them name the same
/// media row, so the media id wins. Paths cover files the scanner has not indexed yet, and the
/// name/size pair is the last resort (the staging folder is flat, so a name is unique there).
String refraEditFileKey({
  required String path,
  required String uri,
  required String fileName,
  required int sizeBytes,
}) {
  final mediaId = uri.startsWith('content://media/') ? _contentMediaIdPattern.firstMatch(uri)?.group(1) : null;
  if (mediaId != null) return 'media:$mediaId';
  if (path.isNotEmpty) return 'path:${path.replaceAll(r'\', '/').toLowerCase()}';
  return 'name:${fileName.toLowerCase()}:$sizeBytes';
}
