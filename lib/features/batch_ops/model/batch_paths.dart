/// Where batch processing writes its results, relative to the primary storage root.
///
/// Kept next to the feature so the layout has one owner: the run sheet builds the
/// output spec from it, the results service records where a result lives, and the
/// album list groups the folder as an app directory from it.
const String batchResultsRelativeRoot = 'Pictures/aves_batch_results';

/// Where copy & share writes its copies, relative to the primary storage root.
///
/// It is deliberately a sibling of the results root: share output is temporary
/// and never actionable, so it must not be recorded as a batch result or offered
/// the results page's replace/move-back decisions.
const String batchShareRelativeRoot = 'Pictures/aves_share';

/// Suffix a superseded result takes while the newer one claims its name.
///
/// Renaming the old file first frees the target name without ever leaving two
/// files that claim it, so the replacement cannot fall back to a MediaStore
/// `(1)` suffix.
const String batchResultSupersededSuffix = '-to-remove';

/// Whether [dirPath] lies inside the batch results tree.
///
/// The tree is this app's output area for derived copies, not a user album, so it
/// is grouped with the other app-owned directories instead of being counted as a
/// normal photo folder.
bool isBatchResultsPath(String dirPath) {
  final normalized = dirPath.replaceAll(r'\', '/').toLowerCase();
  final root = batchResultsRelativeRoot.toLowerCase();
  return normalized.endsWith('/$root') || normalized.contains('/$root/');
}

/// Whether [relativePath] is exactly the results folder.
///
/// The run controller uses this on the output spec, before an absolute path
/// exists, to decide whether an item belongs in the results table.
bool isBatchResultsRelativePath(String relativePath) {
  final normalized = relativePath.replaceAll(r'\', '/').toLowerCase();
  final root = batchResultsRelativeRoot.toLowerCase();
  return normalized == root || normalized == '/$root' || normalized.endsWith('/$root');
}

/// Whether [dirPath] lies inside the copy & share tree.
///
/// Share copies are this app's temporary output, so the folder is grouped with
/// the other app-owned directories and kept out of the user's albums.
bool isBatchSharePath(String dirPath) {
  final normalized = dirPath.replaceAll(r'\', '/').toLowerCase();
  final root = batchShareRelativeRoot.toLowerCase();
  return normalized.endsWith('/$root') || normalized.contains('/$root/');
}

/// Whether [relativePath] is exactly the share folder.
///
/// The run sheet uses this on the output spec, before an absolute path exists,
/// to say where the run will write. A share run is never recorded.
bool isBatchShareRelativePath(String relativePath) {
  final normalized = relativePath.replaceAll(r'\', '/').toLowerCase();
  final root = batchShareRelativeRoot.toLowerCase();
  return normalized == root || normalized == '/$root' || normalized.endsWith('/$root');
}
