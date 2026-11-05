import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';

const _log = AreaKeyLog('log.album_contents_transfer');

/// Carries a completed native folder rename into the library.
///
/// The platform has already moved the folder and kept the row ids, so the
/// database only rewrites the paths it stores, then the album state follows the
/// folder in the same order the batched path applies them (cover, group
/// membership, pin, bookmarks and vault metadata).
///
/// Answers whether the rows followed the folder. The files have moved either
/// way, so a rewrite failure is logged rather than thrown: a later scan or
/// library sync re-reads the paths and the library converges on its own.
Future<bool> applyInstantAlbumRename({
  required CollectionSource source,
  required String album,
  required String destination,
  LocalMediaDb? database,
  Future<void> Function()? reloadSummaries,
}) async {
  var rowsMoved = true;
  try {
    await (database ?? localMediaDb).renameDirectoryPrefix(oldDirectory: album, newDirectory: destination);
  } catch (error, stack) {
    rowsMoved = false;
    _log.e('failed to move rows after renaming $album', error, stack);
  }

  await source.applyStoredAlbumRename(album, destination);
  // The album list and its counts come from the summaries, which reload only
  // on a lens resolve: without this the page keeps the old name until re-entry.
  await (reloadSummaries ?? reloadPagedSummaries)();
  return rowsMoved;
}
