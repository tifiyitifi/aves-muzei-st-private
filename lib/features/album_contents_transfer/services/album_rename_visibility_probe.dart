import 'package:aves/features/album_contents_transfer/model/album_rename_visibility.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_scope.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/services/common/services.dart';

const _log = AreaKeyLog('log.album_contents_transfer');

/// Reads the two counts a whole-folder rename has to compare: the album's
/// visible scope (the very predicate its tile counts, visible range and hidden
/// filters included) and everything its folder holds.
///
/// Answers null when the scope cannot be compiled or the database cannot be
/// read, so the caller keeps the behaviour it had instead of refusing an action
/// on a guess.
///
/// [database] is the seam under test; production callers omit it and use the
/// app-wide [localMediaDb].
Future<AlbumRenameVisibility?> probeAlbumRenameVisibility(StoredAlbumFilter filter, {LocalMediaDb? database}) async {
  final predicate = AlbumContentsScope.predicateFor({filter});
  if (predicate == null) return null;

  final db = database ?? localMediaDb;
  try {
    await db.init();
    final visible = await db.countEntries(predicate);
    final total = await db.countInDirectory(filter.album);
    return AlbumRenameVisibility(visible: visible, total: total);
  } catch (error, stack) {
    _log.w('album rename visibility probe failed', error, stack);
    return null;
  }
}
