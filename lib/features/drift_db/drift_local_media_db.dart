import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/addresses/address_store.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/catalog/catalog_store.dart';
import 'package:aves/features/drift_db/covers/cover_store.dart';
import 'package:aves/features/drift_db/debug/debug_store.dart';
import 'package:aves/features/drift_db/dynamic_albums/dynamic_album_store.dart';
import 'package:aves/features/drift_db/entries/entry_id_allocator.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/drift_db/favourites/favourite_store.dart';
import 'package:aves/features/drift_db/filter_summary/filter_summary_store.dart';
import 'package:aves/features/drift_db/filter_summary/summary_rows.dart';
import 'package:aves/features/drift_db/migration/legacy_import.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/features/drift_db/trash/trash_store.dart';
import 'package:aves/features/drift_db/vaults/vault_store.dart';
import 'package:aves/features/drift_db/video_playback/video_playback_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/favourites.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/viewer/video_playback.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

const _log = AreaKeyLog(LogKeys.db);

/// Composition root and [LocalMediaDb] adapter for the Drift backend.
///
/// Owns the Drift connection and wires the per-domain stores. Every method is a
/// thin delegation; cross-domain work (like [removeIds]) is composed from the
/// stores' own delete operations, so no domain reaches into another's table.
class DriftLocalMediaDb implements LocalMediaDb {
  /// Optional injected database or provider, used by tests to run against an
  /// in-memory connection instead of the on-disk file (which needs a platform
  /// path).
  new({AppDatabase? database, AppDatabaseProvider? provider}) : _provider = provider ?? AppDatabaseProvider(injected: database);

  static const dbFileName = AppDatabaseProvider.dbFileName;

  final AppDatabaseProvider _provider;
  late AppDatabase _db;
  late final EntryStore _entries;
  late final FilterSummaryStore _summaries;
  late final EntryIdAllocator _ids;
  late final CatalogStore _catalog;
  late final AddressStore _addresses;
  late final VaultStore _vaults;
  late final TrashStore _trash;
  late final FavouriteStore _favourites;
  late final CoverStore _covers;
  late final DynamicAlbumStore _dynamicAlbums;
  late final VideoPlaybackStore _videoPlayback;
  late final DebugStore _debug;
  late final AppMetaStore _appMeta;
  Future<void>? _initFuture;

  @override
  int get nextId => _ids.next();

  @override
  Future<String> get path async => pContext.join(await sqflite.getDatabasesPath(), dbFileName);

  /// Opens the database and wires the stores, once.
  ///
  /// Concurrent callers share the in-flight attempt, but a *failed* attempt is
  /// dropped so a later [init] retries: a transient failure of the one-time
  /// legacy import must not poison the instance for the rest of the process.
  @override
  Future<void> init() async {
    final attempt = _initFuture ??= _initialize();
    try {
      await attempt;
    } catch (_) {
      if (identical(_initFuture, attempt)) _initFuture = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    _db = await _provider.open();
    _wireStores();

    if (!_provider.isInjected) {
      final databasesPath = await sqflite.getDatabasesPath();
      final legacyPath = pContext.join(databasesPath, LegacyImport.legacyDbFileName);
      try {
        await LegacyImport(_db, _appMeta).runIfNeeded(
          legacyPath: legacyPath,
          onProgress: (progress) => legacyImportProgress.value = progress,
        );
      } finally {
        // Never leave a stale indicator if the import fails.
        legacyImportProgress.value = null;
      }
    }

    await _ids.init();
  }

  void _wireStores() {
    _entries = EntryStore(_db);
    _summaries = FilterSummaryStore(_db);
    _catalog = CatalogStore(_db);
    _addresses = AddressStore(_db);
    _vaults = VaultStore(_db);
    _trash = TrashStore(_db);
    _favourites = FavouriteStore(_db);
    _covers = CoverStore(_db);
    _dynamicAlbums = DynamicAlbumStore(_db);
    _videoPlayback = VideoPlaybackStore(_db);
    _debug = DebugStore(_db);
    _appMeta = AppMetaStore(_db);
    _ids = EntryIdAllocator(_db, _entries, _appMeta);
  }

  @override
  Future<int> dbFileSize() async {
    final file = File(await path);
    return await file.exists() ? await file.length() : 0;
  }

  @override
  Future<void> reset() async {
    _log.d('$runtimeType reset');
    await _provider.close();
    await sqflite.deleteDatabase(await path);
    _initFuture = null;
    await init();
  }

  @override
  Future<void> removeIds(Set<int> ids, {Set<EntryDataType>? dataTypes}) async {
    if (ids.isEmpty) return;
    final types = dataTypes ?? EntryDataType.values.toSet();
    // A delete is invisible to the write path (the rows are gone), so the group
    // identity of the deleted rows is captured first: losing the tile of a group
    // hands it to another frame, and losing the last of a pair clears it.
    final paths = types.contains(EntryDataType.basic) ? await _entries.pathsOf(ids) : const <String?>[];
    await _db.batch((batch) {
      for (final id in ids) {
        if (types.contains(EntryDataType.basic)) {
          _entries.deleteInBatch(batch, id);
        }
        if (types.contains(EntryDataType.catalog)) {
          _catalog.deleteInBatch(batch, id);
        }
        if (types.contains(EntryDataType.address)) {
          _addresses.deleteInBatch(batch, id);
        }
        if (types.contains(EntryDataType.references)) {
          _favourites.deleteInBatch(batch, id);
          _covers.deleteByEntryIdInBatch(batch, id);
          _trash.deleteInBatch(batch, id);
          _videoPlayback.deleteInBatch(batch, id);
        }
      }
    });
    if (paths.isNotEmpty) {
      await _entries.reindexPaths(paths);
    }
  }

  // entries

  @override
  Future<void> clearEntries() => _entries.clear();

  @override
  Future<Set<AvesEntry>> loadEntries({int? origin, String? directory}) => _entries.load(origin: origin, directory: directory);

  @override
  Future<Set<AvesEntry>> loadEntriesById(Set<int> ids) => _entries.loadByIds(ids);

  @override
  Future<Set<AvesEntry>> loadEntriesByUris(Set<String> uris) => _entries.loadByUris(uris);

  @override
  Future<Set<AvesEntry>> loadEntriesByContentIds(Set<int> ids) => _entries.loadByContentIds(ids);

  @override
  Future<List<AlbumSummaryRow>> loadAlbumSummaryRows(SummaryExclusion exclusion) => _summaries.albumRows(exclusion);

  @override
  Future<List<TagSummaryRow>> loadTagSummaryRows(SummaryExclusion exclusion) => _summaries.tagRows(exclusion);

  @override
  Future<List<CountrySummaryRow>> loadCountrySummaryRows(SummaryExclusion exclusion) => _summaries.countryRows(exclusion);

  @override
  Future<List<StateSummaryRow>> loadStateSummaryRows(SummaryExclusion exclusion) => _summaries.stateRows(exclusion);

  @override
  Future<List<PlaceSummaryRow>> loadPlaceSummaryRows(SummaryExclusion exclusion) => _summaries.placeRows(exclusion);

  @override
  Future<List<String>> loadMimeTypes(SummaryExclusion exclusion) => _summaries.mimeTypes(exclusion);

  @override
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) => _entries.count(predicate: predicate);

  @override
  Future<List<AvesEntry>> loadEntryWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    String? directoryEquals,
    bool directoryEqualsNull = false,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
    required SortFactor sort,
    required bool reverse,
    required int limit,
    required int offset,
  }) =>
      _entries.loadWindow(
        predicate: predicate,
        directoryEquals: directoryEquals,
        directoryEqualsNull: directoryEqualsNull,
        dateFromMillis: dateFromMillis,
        dateToMillis: dateToMillis,
        ratingEquals: ratingEquals,
        sort: sort,
        reverse: reverse,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<AvesEntry>> loadWalkWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required int afterId,
    required int limit,
  }) =>
      _entries.loadWalkWindow(predicate: predicate, afterId: afterId, limit: limit);

  @override
  Future<List<SectionHeader>> loadSectionHeaders({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required SectionGrouping grouping,
    required bool reverse,
  }) =>
      _entries.loadSectionHeaders(predicate: predicate, grouping: grouping, reverse: reverse);

  @override
  Future<bool> hasStackedEntries() => _entries.hasStacks();

  @override
  Future<void> rebuildStackKeys() => _entries.rebuildStackKeys();

  @override
  Future<Map<int, List<AvesEntry>>> loadStackMembers(Set<int> ids) => _entries.loadStackMembers(ids);

  @override
  Future<int> countDays({required CollectionWindowPredicate predicate}) => _entries.countDays(predicate: predicate);

  @override
  Future<List<AvesEntry>> loadDayWindow({required CollectionWindowPredicate predicate, int? dateFromMillis, int? dateToMillis, required bool reverse, required int limit, required int offset}) =>
      _entries.loadDayWindow(predicate: predicate, dateFromMillis: dateFromMillis, dateToMillis: dateToMillis, reverse: reverse, limit: limit, offset: offset);

  @override
  Future<List<SectionHeader>> loadDaySectionHeaders({required CollectionWindowPredicate predicate, required bool reverse}) => _entries.loadDaySectionHeaders(predicate: predicate, reverse: reverse);

  @override
  Future<Float32List> loadRatioChannel({required CollectionWindowPredicate predicate, String? directoryEquals, bool directoryEqualsNull = false, int? dateFromMillis, int? dateToMillis, int? ratingEquals, required SortFactor sort, required bool reverse}) =>
      _entries.loadRatioChannel(predicate: predicate, directoryEquals: directoryEquals, directoryEqualsNull: directoryEqualsNull, dateFromMillis: dateFromMillis, dateToMillis: dateToMillis, ratingEquals: ratingEquals, sort: sort, reverse: reverse);

  @override
  Future<int> countDaysBefore({required CollectionWindowPredicate predicate, required int id, required bool reverse}) => _entries.countDaysBefore(predicate: predicate, id: id, reverse: reverse);

  @override
  Future<Map<DateTime, List<AvesEntry>>> loadDayMembers({required CollectionWindowPredicate predicate, required Set<DateTime> days, required bool reverse}) =>
      _entries.loadDayMembers(predicate: predicate, days: days, reverse: reverse);

  @override
  Future<int> countEntriesBefore({
    required CollectionWindowPredicate predicate,
    required int id,
    required SortFactor sort,
    required bool reverse,
  }) =>
      _entries.countBefore(predicate: predicate, id: id, sort: sort, reverse: reverse);

  @override
  Future<({int count, int sizeBytes, int maxBestDate})> aggregateEntries(CollectionWindowPredicate predicate) => _entries.aggregate(predicate: predicate);

  @override
  Future<void> insertEntries(Set<AvesEntry> entries) => _entries.insertAll(entries);

  @override
  Future<void> updateEntry(int id, AvesEntry entry) => _entries.update(id, entry);

  @override
  Future<Set<AvesEntry>> searchLiveEntries(String query, {int? limit}) => _entries.searchLive(query, limit: limit);

  @override
  Future<Set<AvesEntry>> searchLiveDuplicates(int origin, Set<AvesEntry>? entries) => _entries.searchDuplicates(origin, entries);

  // date taken

  @override
  Future<void> clearDates() => _catalog.clearDates();

  @override
  Future<Map<int?, int?>> loadDates() => _catalog.loadDates();

  // catalog metadata

  @override
  Future<void> clearCatalogMetadata() => _catalog.clearMetadata();

  @override
  Future<Set<CatalogMetadata>> loadCatalogMetadata() => _catalog.loadAll();

  @override
  Future<Set<CatalogMetadata>> loadCatalogMetadataById(Set<int> ids) => _catalog.loadByIds(ids);

  @override
  Future<void> saveCatalogMetadata(Set<CatalogMetadata> metadataEntries) => _catalog.save(metadataEntries);

  @override
  Future<void> updateCatalogMetadata(int id, CatalogMetadata? metadata) => _catalog.update(id, metadata);

  @override
  Future<int> countUncatalogued([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) => _entries.countUncatalogued(predicate);

  @override
  Future<List<int>> loadUncataloguedEntryIds({CollectionWindowPredicate predicate = const CollectionWindowPredicate(), required int afterId, required int limit}) =>
      _entries.loadUncataloguedEntryIds(predicate: predicate, afterId: afterId, limit: limit);

  // address

  @override
  Future<void> clearAddresses() => _addresses.clear();

  @override
  Future<Set<AddressDetails>> loadAddresses() => _addresses.loadAll();

  @override
  Future<Set<AddressDetails>> loadAddressesById(Set<int> ids) => _addresses.loadByIds(ids);

  @override
  Future<void> saveAddresses(Set<AddressDetails> addresses) => _addresses.save(addresses);

  @override
  Future<void> updateAddress(int id, AddressDetails? address) => _addresses.update(id, address);

  @override
  Future<List<int>> loadUnaddressedGpsIds({CollectionWindowPredicate predicate = const CollectionWindowPredicate(), required int afterId, required int limit}) => _entries.loadUnaddressedGpsIds(predicate: predicate, afterId: afterId, limit: limit);

  @override
  Future<List<int>> loadUnlocatedGpsIds({CollectionWindowPredicate predicate = const CollectionWindowPredicate(), required int afterId, required int limit}) => _entries.loadUnlocatedGpsIds(predicate: predicate, afterId: afterId, limit: limit);

  // vaults

  @override
  Future<void> clearVaults() => _vaults.clear();

  @override
  Future<Set<VaultDetails>> loadAllVaults() => _vaults.loadAll();

  @override
  Future<void> addVaults(Set<VaultDetails> rows) => _vaults.add(rows);

  @override
  Future<void> updateVault(String oldName, VaultDetails row) => _vaults.update(oldName, row);

  @override
  Future<void> removeVaults(Set<VaultDetails> rows) => _vaults.remove(rows);

  // trash

  @override
  Future<void> clearTrashDetails() => _trash.clear();

  @override
  Future<Set<TrashDetails>> loadAllTrashDetails() => _trash.loadAll();

  @override
  Future<void> updateTrash(int id, TrashDetails? details) => _trash.update(id, details);

  // favourites

  @override
  Future<void> clearFavourites() => _favourites.clear();

  @override
  Future<Set<FavouriteRow>> loadAllFavourites() => _favourites.loadAll();

  @override
  Future<void> addFavourites(Set<FavouriteRow> rows) => _favourites.add(rows);

  @override
  Future<void> updateFavouriteId(int id, FavouriteRow row) => _favourites.updateId(id, row);

  @override
  Future<void> removeFavourites(Set<FavouriteRow> rows) => _favourites.remove(rows);

  // covers

  @override
  Future<void> clearCovers() => _covers.clear();

  @override
  Future<Set<CoverRow>> loadAllCovers() => _covers.loadAll();

  @override
  Future<void> addCovers(Set<CoverRow> rows) => _covers.add(rows);

  @override
  Future<void> updateCoverEntryId(int id, CoverRow row) => _covers.updateEntryId(id, row);

  @override
  Future<void> removeCovers(Set<CollectionFilter> filters) => _covers.remove(filters);

  // dynamic albums

  @override
  Future<int> clearDynamicAlbums() => _dynamicAlbums.clear();

  @override
  Future<Set<DynamicAlbumRow>> loadAllDynamicAlbums() => _dynamicAlbums.loadAll();

  @override
  Future<void> addDynamicAlbums(Set<DynamicAlbumRow> rows) => _dynamicAlbums.add(rows);

  @override
  Future<void> removeDynamicAlbums(Set<String> names) => _dynamicAlbums.remove(names);

  // video playback

  @override
  Future<void> clearVideoPlayback() => _videoPlayback.clear();

  @override
  Future<Set<VideoPlaybackRow>> loadAllVideoPlayback() => _videoPlayback.loadAll();

  @override
  Future<VideoPlaybackRow?> loadVideoPlayback(int id) => _videoPlayback.load(id);

  @override
  Future<void> addVideoPlayback(Set<VideoPlaybackRow> rows) => _videoPlayback.add(rows);

  @override
  Future<void> removeVideoPlayback(Set<int> ids) => _videoPlayback.remove(ids);

  // debug

  @override
  Future<void> clearDebugLog() => _debug.clear();

  @override
  Future<List<String>> loadAllDebugLog() => _debug.loadAll();

  @override
  Future<void> addDebugLog(String message) => _debug.add(message);
}
