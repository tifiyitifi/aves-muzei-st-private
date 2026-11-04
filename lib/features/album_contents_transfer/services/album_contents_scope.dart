import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/services/common/services.dart';

const _log = AreaKeyLog('log.album_contents_transfer');

/// The database scope behind a set of selected albums.
///
/// The album grid renders summaries, not entries, so on a windowed collection an
/// action over several albums owns no entry list to work from. The database can
/// still answer exactly: the union of the albums is one SQL predicate, and the
/// per-album counts and sizes are the same rows the album tiles show. The scope
/// is frozen at this point, so the action walks what the user saw.
class AlbumContentsScope {
  /// The union of [countByAlbum]'s albums, as the windowed view resolves it.
  final CollectionWindowPredicate predicate;

  /// Visible entries per selected album, zero when the album has none.
  final Map<String, int> countByAlbum;

  /// Total bytes of the visible entries per selected album, for the free-space
  /// check a copy needs.
  final Map<String, int> sizeByAlbum;

  const new _({
    required this.predicate,
    required this.countByAlbum,
    required this.sizeByAlbum,
  });

  int get entryCount => countByAlbum.values.fold(0, (sum, count) => sum + count);

  /// Total bytes of every selected album's visible entries.
  int get sizeBytes => sizeByAlbum.values.fold(0, (sum, size) => sum + size);

  int countIn(String album) => countByAlbum[album] ?? 0;

  int sizeIn(String album) => sizeByAlbum[album] ?? 0;

  /// The union predicate of [albums], or null when the scope needs the in-memory
  /// path (a filter the SQL layer cannot express).
  static CollectionWindowPredicate? predicateFor(Set<StoredAlbumFilter> albums) {
    if (albums.isEmpty) return null;
    final filters = albums.length > 1 ? {SetOrFilter(albums.toSet())} : albums.toSet();
    return const CollectionEngineRouter().predicateForScope(filters);
  }

  /// Probes [albums] into a scope, or null when the caller must keep the
  /// in-memory path because the scope cannot be expressed or read.
  ///
  /// [database] is the seam under test; production callers omit it and use the
  /// app-wide [localMediaDb].
  static Future<AlbumContentsScope?> resolve(Set<StoredAlbumFilter> albums, {LocalMediaDb? database}) async {
    final predicate = predicateFor(albums);
    if (predicate == null) return null;
    final db = database ?? localMediaDb;
    try {
      await db.init();
      final countByAlbum = <String, int>{};
      final sizeByAlbum = <String, int>{};
      for (final album in albums) {
        final albumPredicate = predicateFor({album});
        // An album compiles exactly like its union does, so this cannot differ;
        // answering null keeps the caller on the path that cannot disagree.
        if (albumPredicate == null) return null;
        final aggregate = await db.aggregateEntries(albumPredicate);
        countByAlbum[album.album] = aggregate.count;
        sizeByAlbum[album.album] = aggregate.sizeBytes;
      }
      return AlbumContentsScope._(
        predicate: predicate,
        countByAlbum: countByAlbum,
        sizeByAlbum: sizeByAlbum,
      );
    } catch (error, stack) {
      _log.w('album scope probe failed', error, stack);
      return null;
    }
  }
}
