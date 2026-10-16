import 'package:aves/features/logging/log.dart';
import 'package:aves/geo/countries.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/catalog.dart';
import 'package:aves/model/entry/extensions/location.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/location/location.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';

const _log = AreaKeyLog('log.collection_paging');

/// Background catalog + offline-country worker for paged collections.
///
/// The grid paints instantly from the MediaStore mirror (no per-file I/O),
/// while this worker fills in the deep metadata underneath in bounded chunks:
/// tags, precise dates and ratings via [catalogEntry], countries via
/// [locateCountry]. Resumable: finished rows are skipped by the keyset range
/// queries, so an interrupted run continues instead of restarting.
///
/// Cadence mirrors the legacy `analyze` path (`TagMixin`/`LocationMixin`
/// thresholds), and completion flows through the same source events, so the
/// lens refresh and summary reload need no new wiring.
class PagedCatalogWorker {
  final CollectionSource source;
  final LocalMediaDb database;
  final Future<void> Function(AvesEntry entry) catalogEntry;
  final Future<AddressDetails?> Function(AvesEntry entry) locateCountry;

  bool _running = false;
  bool _stopRequested = false;

  new({
    required this.source,
    LocalMediaDb? database,
    Future<void> Function(AvesEntry entry)? catalogEntry,
    Future<AddressDetails?> Function(AvesEntry entry)? locateCountry,
  })  : database = database ?? localMediaDb,
        catalogEntry = catalogEntry ?? _defaultCatalogEntry,
        locateCountry = locateCountry ?? _defaultLocateCountry;

  static Future<void> _defaultCatalogEntry(AvesEntry entry) => entry.catalog(background: true, force: false, persist: true);

  static Future<AddressDetails?> _defaultLocateCountry(AvesEntry entry) async {
    if (!entry.hasGps || entry.hasAddress) return null;
    entry.setCountry(await countryTopology.countryCode(entry.latLng!));
    return entry.addressDetails;
  }

  bool get isRunning => _running;

  /// Runs the catalog backlog, then the offline-country backlog. No-op while
  /// a run is in flight; [stop] cooperatively halts between chunks.
  Future<void> run({int chunkSize = 200}) async {
    if (_running) return;
    _running = true;
    _stopRequested = false;
    try {
      await _runCatalog(chunkSize);
      if (!_stopRequested) await _runCountries(chunkSize);
    } finally {
      _running = false;
      source.state = SourceState.ready;
    }
  }

  void stop() => _stopRequested = true;

  Future<void> _runCatalog(int chunkSize) async {
    final total = await database.countUncatalogued();
    if (total == 0) return;
    var afterId = 0;
    var done = 0;
    var stopCheckCount = 0;
    final pending = <CatalogMetadata>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveCatalogMetadata(Set.unmodifiable(pending));
      source.onCatalogMetadataChanged();
      pending.clear();
    }

    source.state = SourceState.cataloguing;
    source.setProgress(done: 0, total: total);
    while (!_stopRequested) {
      final ids = await database.loadUncataloguedEntryIds(afterId: afterId, limit: chunkSize);
      if (ids.isEmpty) break;
      afterId = ids.last;
      for (final entry in await _materialize(ids.toSet())) {
        try {
          await catalogEntry(entry);
          if (entry.isCatalogued) pending.add(entry.catalogMetadata!);
        } catch (error, stack) {
          _log.w('paged catalog failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= TagMixin.commitCountThreshold) await flush();
        if (++stopCheckCount >= 100) {
          stopCheckCount = 0;
          if (_stopRequested) break;
        }
      }
      done += ids.length;
      source.setProgress(done: done, total: total);
      // Cooperative yield between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  Future<void> _runCountries(int chunkSize) async {
    var afterId = 0;
    var done = 0;
    final pending = <AddressDetails>{};
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await database.saveAddresses(Set.unmodifiable(pending));
      source.onAddressMetadataChanged();
      pending.clear();
    }

    source.state = SourceState.locatingCountries;
    source.setProgress(done: 0, total: 0);
    while (!_stopRequested) {
      final ids = await database.loadUnaddressedGpsIds(afterId: afterId, limit: chunkSize);
      if (ids.isEmpty) break;
      afterId = ids.last;
      for (final entry in await _materialize(ids.toSet())) {
        try {
          final address = await locateCountry(entry);
          if (address != null) pending.add(address);
        } catch (error, stack) {
          _log.w('paged locate failed for entry id=${entry.id}', error, stack);
        } finally {
          entry.dispose();
        }
        if (pending.length >= LocationMixin.commitCountThreshold) await flush();
      }
      done += ids.length;
      source.setProgress(done: done, total: 0);
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  /// Materializes one chunk with catalog metadata attached (drives
  /// `hasGps`/`latLng` for the country pass). Owned by the worker: callers
  /// dispose every entry after use.
  Future<Set<AvesEntry>> _materialize(Set<int> ids) async {
    final entries = await database.loadEntriesById(ids);
    if (entries.isEmpty) return entries;
    final metaById = {for (final m in await database.loadCatalogMetadataById(ids)) m.id: m};
    for (final entry in entries) {
      entry.catalogMetadata = metaById[entry.id];
    }
    return entries;
  }
}
