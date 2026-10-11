import 'dart:io';

import 'package:aves/features/drift_db/addresses/address_store.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/catalog/catalog_store.dart';
import 'package:aves/features/drift_db/covers/cover_store.dart';
import 'package:aves/features/drift_db/debug/debug_store.dart';
import 'package:aves/features/drift_db/dynamic_albums/dynamic_album_store.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:aves/features/drift_db/favourites/favourite_store.dart';
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
  static int _lastId = 0;

  final AppDatabaseProvider _provider;
  late AppDatabase _db;
  late final EntryStore _entries;
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
  int get nextId => ++_lastId;

  @override
  Future<String> get path async => pContext.join(await sqflite.getDatabasesPath(), dbFileName);

  @override
  Future<void> init() => _initFuture ??= _initialize();

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

    _lastId = await _entries.maxId();
  }

  void _wireStores() {
    _entries = EntryStore(_db);
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
  }

  // entries

  @override
  Future<void> clearEntries() => _entries.clear();

  @override
  Future<Set<AvesEntry>> loadEntries({int? origin, String? directory}) => _entries.load(origin: origin, directory: directory);

  @override
  Future<Set<AvesEntry>> loadEntriesById(Set<int> ids) => _entries.loadByIds(ids);

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
