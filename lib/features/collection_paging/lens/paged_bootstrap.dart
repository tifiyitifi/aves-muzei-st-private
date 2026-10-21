import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/favourites.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/grouping/common.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Startup essentials for a paged collection view, without materializing
/// entries.
///
/// Mirrors `MediaStoreSource._loadEssentials` ordering (stores, groupings,
/// covers, timezone parity, catalog dates, pinned albums, generation) but
/// never loads entries: totals, headers and windows resolve on demand. All
/// calls use public APIs so the upstream load path is untouched. Monitoring
/// stays paused — MediaStore changes cannot materialize rows the database
/// does not know about yet (fresh discovery is a later step).
class PagedBootstrap {
  static bool _essentialsDone = false;

  /// [driveState] lets a parked view reuse the essentials without touching the
  /// library-wide state: the page on screen owns that, and a background resolve
  /// settling it would flip another page's app bar to "ready".
  static Future<void> ensure(CollectionSource source, {bool driveState = true}) async {
    final stopwatch = Stopwatch()..start();
    await localMediaDb.init();
    if (!_essentialsDone) {
      await vaults.init();
      await favourites.init();
      albumGrouping.init();
      albumGrouping.setGroups(settings.albumGroups);
      albumGrouping.registerSource(source);
      tagGrouping.init();
      tagGrouping.setGroups(settings.tagGroups);
      tagGrouping.registerSource(source);
      await covers.init();
      await dynamicAlbums.init();
      _essentialsDone = true;
    } else {
      albumGrouping.registerSource(source);
      tagGrouping.registerSource(source);
    }

    final deviceOffset = DateTime.now().timeZoneOffset.inMilliseconds;
    final catalogOffset = settings.catalogTimeZoneOffsetMillis;
    final datesInvalidated = deviceOffset != catalogOffset;
    if (datesInvalidated) {
      await localMediaDb.clearDates();
      await localMediaDb.clearCatalogMetadata();
      settings.catalogTimeZoneOffsetMillis = deviceOffset;
    }
    await source.loadDates(force: datesInvalidated);

    source.addDirectories(albums: settings.pinnedFilters.whereType<StoredAlbumFilter>().map((v) => v.album).toSet());
    if (source is MediaStoreSource) {
      // Bounded like the resolve's own media store steps: this is a platform
      // query, and a reply lost while the engine restarts must not hold the
      // whole bootstrap (and every view waiting on it).
      await withPlatformTimeout(source.updateGeneration, label: 'media store generation');
    }
    source.pauseMonitoring();
    if (driveState) source.state = SourceState.ready;
    source.notifyAlbumsChanged();
    _log.d('paged bootstrap complete in ${stopwatch.elapsed.inMilliseconds}ms');
  }

  /// Feeds the source directory list from album headers so drawer navigation
  /// and album links keep working with an entry-free source.
  static void feedDirectories(CollectionSource source, List<SectionHeader> headers) {
    source.addDirectories(albums: headers.map((h) => h.directory).whereType<String>().toSet());
  }
}
