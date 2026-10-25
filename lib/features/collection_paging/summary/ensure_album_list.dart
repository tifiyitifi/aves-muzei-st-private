import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/source/collection_source.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// Makes [source] answer its album list, whichever engine owns it.
///
/// An entry-free (paged) source keeps no directories in memory: the database
/// provider is its album list. The provider is attached by a paged lens, so a
/// page reached without one — the album destination opened from the bottom bar,
/// or a wallpaper pick that starts on the album list — reads an empty source and
/// paints "no albums" over a library that has them.
///
/// Loads the album domain and, when the source is entry-free and publication is
/// allowed, attaches the provider first. A fully loaded source is left alone: its
/// in-memory directories are the authoritative list, and switching it to the
/// database behind a legacy view would make counts disagree with the entries the
/// view shows.
Future<void> ensureAlbumListData(CollectionSource source) async {
  final summaries = source.summaries;
  if (summaries != null) {
    await summaries.ensureAlbums();
    return;
  }
  // A full load ran: the source materialized its entries, so `_directories` is
  // the album list. `targetScope` is only set by that load.
  if (source.targetScope != null || source.allEntries.isNotEmpty) return;
  // While the browser owns the library surface the album page shows it instead,
  // and the database is a partial answer.
  if (libraryPhase.isBrowsing) return;
  _log.d('album list attached the paged summaries for an entry-free source');
  attachPagedSummaries(source);
  await source.summaries?.ensureAlbums();
}
