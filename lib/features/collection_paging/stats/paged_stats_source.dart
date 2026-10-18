import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/stats/collection_stats.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';

const _log = AreaKeyLog('log.collection_paging.stats');

/// Statistics of a collection scope, streamed from the database.
///
/// Built at a composition root when the scope is windowed: the stats page then
/// renders the aggregate instead of walking its in-memory entries, and the
/// export streams the rows it needs. Both work in bounded chunks, so a scope of
/// millions of rows never has to be materialized.
///
/// The walk counts the scope's own rows. The in-memory page instead expands the
/// stacks it shows, so a burst frame the scope *excludes* while its tile is in
/// scope is counted there and not here: the two differ by those frames, which
/// takes a filter that splits a burst group (a rating or tag filter, say). A
/// matching SQL expansion would re-evaluate the scope per chunk, which is the
/// cost this walk exists to avoid.
class PagedStatsSource {
  /// Rows per chunk: one chunk is one query plus one metadata round-trip, so it
  /// bounds the memory and the latency of a walk at the same time.
  static const defaultChunkSize = 2000;

  /// The scope's predicate, as the windowed view resolves it.
  final CollectionWindowPredicate predicate;

  /// The scope's total, so progress needs no recount.
  final int entryCount;

  /// Rows read per query, and per metadata round-trip.
  final int chunkSize;

  const new({
    required this.predicate,
    required this.entryCount,
    this.chunkSize = defaultChunkSize,
  });

  /// Folds the whole scope into one aggregate.
  ///
  /// [onProgress] reports the rows folded so far against [entryCount], so a
  /// huge scope can show how far it is.
  Future<CollectionStats> load({void Function(int done, int total)? onProgress}) async {
    final accumulator = CollectionStatsAccumulator(settings.calendar);
    var done = 0;
    await for (final rows in _walk()) {
      for (final row in rows) {
        accumulator.add(row);
      }
      done += rows.length;
      onProgress?.call(done, entryCount);
    }
    return accumulator.build();
  }

  /// The scope's entries, in bounded chunks, carrying their deep metadata.
  ///
  /// For a caller that needs the entries themselves rather than their aggregate
  /// (the export). One chunk is attached at a time, so the caller never holds
  /// the whole scope, and a chunk that has been consumed can be dropped.
  Stream<List<AvesEntry>> streamEntries() async* {
    await for (final rows in _walk()) {
      _attach(rows);
      yield [for (final row in rows) row.entry];
    }
  }

  /// The scope's first row, for the export's field preview.
  Future<AvesEntry?> firstEntry() async {
    final entries = await localMediaDb.loadWalkWindow(predicate: predicate, afterId: 0, limit: 1);
    if (entries.isEmpty) return null;
    final rows = await _withMetadata(entries);
    _attach(rows);
    return rows.first.entry;
  }

  /// The scope's rows, in bounded id-ordered chunks, with the metadata and
  /// address of each chunk loaded alongside it.
  Stream<List<StatsRow>> _walk() async* {
    var afterId = 0;
    while (true) {
      final entries = await localMediaDb.loadWalkWindow(predicate: predicate, afterId: afterId, limit: chunkSize);
      if (entries.isEmpty) break;
      yield await _withMetadata(entries);
      if (entries.length < chunkSize) break;
      afterId = entries.last.id;
    }
  }

  /// Pairs [entries] with their metadata and address rows.
  ///
  /// A failed lookup degrades the chunk to entries without metadata rather than
  /// failing the walk: a stats page with a few uncatalogued rows beats no page.
  static Future<List<StatsRow>> _withMetadata(List<AvesEntry> entries) async {
    final ids = {for (final entry in entries) entry.id};
    Map<int, CatalogMetadata> metaById = {};
    Map<int, AddressDetails> addressById = {};
    try {
      metaById = {for (final m in await localMediaDb.loadCatalogMetadataById(ids)) m.id: m};
      addressById = {for (final a in await localMediaDb.loadAddressesById(ids)) a.id: a};
    } catch (error, stack) {
      _log.w('stats metadata load failed', error, stack);
    }
    return [for (final entry in entries) (entry: entry, metadata: metaById[entry.id], address: addressById[entry.id])];
  }

  /// Attaches the metadata to the entries, for a caller that needs the entry's
  /// catalogued face (the export's fields and preview).
  ///
  /// The aggregate does not attach: `AvesEntry.catalogMetadata` evicts the image
  /// cache and clears the platform decoders, which is fine for a screenful of
  /// tiles but not for a whole library.
  static void _attach(List<StatsRow> rows) {
    for (final row in rows) {
      final metadata = row.metadata;
      if (metadata != null) row.entry.catalogMetadata = metadata;
      final address = row.address;
      if (address != null) row.entry.addressDetails = address;
    }
  }
}

/// The windowed stats of [filters], or null when the scope must use the
/// in-memory path (a small library, an uncompilable filter, a locked vault, a
/// non-Gregorian section).
///
/// The composition roots resolve the engine before opening the stats page, so
/// the page never has to decide which one serves its scope.
Future<PagedStatsSource?> pagedStatsSourceFor(Set<CollectionFilter> filters) async {
  final decision = await const CollectionEngineRouter().resolve(filters: filters);
  final predicate = decision.predicate;
  if (decision.route != CollectionRoute.paged || predicate == null) return null;
  return PagedStatsSource(predicate: predicate, entryCount: decision.total);
}
