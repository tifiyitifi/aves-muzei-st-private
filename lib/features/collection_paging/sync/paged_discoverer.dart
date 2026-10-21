import 'dart:async';
import 'dart:convert';

import 'package:aves/features/collection_paging/engine/collection_paging_keys.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/catalog.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// MediaStore <-> database sync for paged collections, without materializing
/// the collection.
///
/// Two paths, both bounded by the change size instead of the library size:
/// - [syncIfChanged]: generation-gated. One cheap platform query when quiet;
///   when the generation moved, only the changed URIs round-trip (fetch,
///   obsolete-check and upsert per URI).
/// - [importAll]: chunked full scan for a first launch on an unseen library
///   (or an interrupted one). Streams every row once, upserts per chunk by
///   content id, and skips rows already in the database — so reruns resume
///   instead of duplicating, at any scale.
///
/// The generation cursor persists in `SharedPreferences`, so restarts do not
/// redownload the world.
class PagedDiscoverer {
  final MediaStoreService mediaStore;
  final MediaFetchService mediaFetch;
  final LocalMediaDb database;
  final Future<void> Function(AvesEntry entry) catalogEntry;

  Map<String, int>? _lastGeneration;
  bool _importing = false;
  new({
    MediaStoreService? mediaStore,
    MediaFetchService? mediaFetch,
    LocalMediaDb? database,
    Future<void> Function(AvesEntry entry)? catalogEntry,
  })  : mediaStore = mediaStore ?? mediaStoreService,
        mediaFetch = mediaFetch ?? mediaFetchService,
        database = database ?? localMediaDb,
        catalogEntry = catalogEntry ?? ((entry) => _defaultCatalogEntry(database ?? localMediaDb, entry));

  /// Inline catalog for steady-state changes, mirroring the legacy
  /// `refreshUris -> analyze` path: fresh rows arrive tagged and dated instead
  /// of waiting for the background worker. Failures leave the row
  /// uncatalogued for the worker; never fail the sync.
  static Future<void> _defaultCatalogEntry(LocalMediaDb database, AvesEntry entry) async {
    await entry.catalog(background: true, force: false, persist: true);
    await database.updateCatalogMetadata(entry.id, entry.catalogMetadata);
  }

  /// Generation cursor, for tests.
  @visibleForTesting
  Map<String, int>? get lastGeneration => _lastGeneration;

  @visibleForTesting
  set lastGeneration(Map<String, int>? generation) => _lastGeneration = generation;

  /// Discovers MediaStore changes since the last generation. Returns the
  /// number of applied changes (0 when quiet or untrackable).
  Future<int> syncIfChanged() async {
    final generation = await mediaStore.getGenerationByVolume();
    if (generation == null) return 0;
    final since = _lastGeneration ?? await _readPersistedGeneration();
    if (since == null) {
      await _storeGeneration(generation);
      return 0;
    }
    if (_equalGenerations(since, generation)) return 0;
    final applied = await _syncChanged(since);
    await _storeGeneration(generation);
    return applied;
  }

  /// Chunked full import. Safe to rerun: rows already in the database (by
  /// content id) are skipped, modified ones are overwritten in place.
  ///
  /// [firstBatchLimit] splits the run so a caller can paint before the whole
  /// library is written: once that many rows are in, [onFirstBatch] is awaited
  /// (the caller resolves its view there) and the stream carries on behind it.
  /// The rows arrive newest first, so everything the later batches add lands at
  /// the tail of a date-ordered view instead of reordering what is on screen.
  ///
  /// Returns the number of inserted or updated rows.
  Future<int> importAll({
    required void Function(int done) onProgress,
    int firstBatchLimit = 0,
    Future<void> Function()? onFirstBatch,
  }) async {
    if (_importing) return 0;
    _importing = true;
    final stopwatch = Stopwatch()..start();
    try {
      var processed = 0;
      var written = 0;
      var batch = <AvesEntry>{};
      var signalled = firstBatchLimit <= 0;
      Future<void> flush() async {
        if (batch.isEmpty) return;
        final count = batch.length;
        processed += count;
        written += await _upsertBatch(batch);
        // Progress counts the rows the stream has covered, not the rows it
        // wrote: a resumed run re-walks rows that are already there, and a
        // counter that stalls at 0 while it does would read as stuck.
        onProgress(processed);
        batch = {};
        _log.v('paged import chunk: $count rows in ${stopwatch.elapsedMilliseconds}ms, $processed processed, $written written');
        stopwatch.reset();
        // Cooperative yield: a million-row import must not starve the UI.
        await Future<void>.delayed(Duration.zero);
      }

      // Emitted when the stream ends before reaching the limit (a library
      // smaller than one batch) so the caller is never left waiting.
      Future<void> signalFirstBatch() async {
        if (signalled) return;
        signalled = true;
        await flush();
        if (onFirstBatch != null) await onFirstBatch();
      }

      await for (final entry in mediaStore.getEntries(const {})) {
        entry.id = database.nextId;
        batch.add(entry);
        if (!signalled) {
          if (batch.length >= firstBatchLimit) await signalFirstBatch();
        } else if (batch.length >= 2000) {
          await flush();
        }
      }
      await signalFirstBatch();
      await flush();

      final generation = await mediaStore.getGenerationByVolume();
      if (generation != null) await _storeGeneration(generation);
      return written;
    } finally {
      _importing = false;
    }
  }

  /// Counts the rows [importAll] would stream, for the import progress
  /// denominator. 0 when the platform cannot tell.
  Future<int> countEntries() async {
    try {
      return await mediaStore.countEntries();
    } catch (error, stack) {
      _log.w('paged entry count failed', error, stack);
      return 0;
    }
  }

  /// Applies one batch: existing rows (by content id) are overwritten when
  /// modified, missing rows are inserted, trash details are attached.
  /// Returns the number of written rows.
  Future<int> _upsertBatch(Set<AvesEntry> batch) async {
    if (batch.isEmpty) return 0;
    // MediaStore normally identifies a row by content id, but a provider that
    // reports none must not lose the row: the URI identifies it just as well,
    // and the change-sync path already inserts rows without a content id.
    final byContentId = <int, AvesEntry>{};
    final byUri = <String, AvesEntry>{};
    for (final entry in batch) {
      final contentId = entry.contentId;
      if (contentId != null) {
        byContentId[contentId] = entry;
      } else {
        byUri[entry.uri] = entry;
      }
    }
    final knownByContentId = {
      for (final entry in await database.loadEntriesByContentIds(byContentId.keys.toSet())) entry.contentId: entry,
    };
    final knownByUri = byUri.isEmpty
        ? <String, AvesEntry>{}
        : {
            for (final entry in await database.loadEntriesByUris(byUri.keys.toSet()))
              // Only rows this import owns: a vault row can carry the same URI
              // and must not be overwritten with a media-store one.
              if (entry.origin == EntryOrigins.mediaStoreContent) entry.uri: entry,
          };

    final toInsert = <AvesEntry>{};
    var written = 0;

    Future<void> upsert(AvesEntry entry, AvesEntry? knownEntry) async {
      if (knownEntry == null) {
        toInsert.add(entry);
        return;
      }
      if ((entry.dateModifiedMillis ?? 0) <= (knownEntry.dateModifiedMillis ?? 0)) return;
      entry.id = knownEntry.id;
      await database.updateEntry(knownEntry.id, entry);
      await _saveTrash(entry);
      written++;
    }

    for (final kv in byContentId.entries) {
      await upsert(kv.value, knownByContentId[kv.key]);
    }
    for (final kv in byUri.entries) {
      await upsert(kv.value, knownByUri[kv.key]);
    }
    if (toInsert.isNotEmpty) {
      await database.insertEntries(toInsert);
      for (final entry in toInsert) {
        await _saveTrash(entry);
      }
      written += toInsert.length;
    }
    return written;
  }

  Future<void> _saveTrash(AvesEntry entry) async {
    final trashDetails = entry.trashDetails;
    if (entry.trashed && trashDetails != null) {
      await database.updateTrash(entry.id, trashDetails);
    }
  }

  /// Syncs exactly the URIs changed since [sinceGeneration].
  Future<int> _syncChanged(Map<String, int> sinceGeneration) async {
    final changedUris = await mediaStore.getChangedUris(sinceGeneration);
    if (changedUris.isEmpty) return 0;
    var applied = 0;
    for (final uri in changedUris) {
      try {
        if (await _syncUri(uri)) applied++;
      } catch (error, stack) {
        _log.w('paged sync failed for uri=$uri', error, stack);
      }
      // Cooperative yield between platform round-trips.
      await Future<void>.delayed(Duration.zero);
    }
    return applied;
  }

  /// Returns true when [uri] produced a database write.
  Future<bool> _syncUri(String uri) async {
    final entry = await mediaFetch.getEntry(uri, null);
    if (entry == null) {
      return _removeObsoleteUri(uri);
    }
    final contentId = entry.contentId;
    if (contentId != null) {
      final known = await database.loadEntriesByContentIds({contentId});
      final existing = known.firstOrNull;
      if (existing != null) {
        if ((entry.dateModifiedMillis ?? 0) <= (existing.dateModifiedMillis ?? 0) && existing.path == entry.path) {
          return false;
        }
        entry.id = existing.id;
        try {
          await catalogEntry(entry);
        } catch (error, stack) {
          _log.w('paged sync catalog failed for uri=$uri', error, stack);
        }
        await database.updateEntry(existing.id, entry);
        await _saveTrash(entry);
        return true;
      }
    }
    entry.id = database.nextId;
    entry.origin = EntryOrigins.mediaStoreContent;
    try {
      await catalogEntry(entry);
    } catch (error, stack) {
      _log.w('paged sync catalog failed for uri=$uri', error, stack);
    }
    await database.insertEntries({entry});
    await _saveTrash(entry);
    return true;
  }

  /// Removes the row for a vanished [uri] (content id parsed like the legacy
  /// refresh path does), if it is still tracked.
  Future<bool> _removeObsoleteUri(String uri) async {
    final contentId = int.tryParse(Uri.parse(uri).pathSegments.lastOrNull ?? '');
    if (contentId == null) return false;
    final obsolete = await mediaStore.checkObsoleteContentIds([contentId]);
    if (!obsolete.contains(contentId)) return false;
    final known = await database.loadEntriesByContentIds({contentId});
    if (known.isEmpty) return false;
    await database.removeIds(known.map((e) => e.id).toSet());
    return true;
  }

  static bool _equalGenerations(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }

  Future<Map<String, int>?> _readPersistedGeneration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(CollectionPagingKeys.mediaGeneration);
      if (raw == null || raw.isEmpty) return _lastGeneration;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _lastGeneration;
      return _lastGeneration = decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (error, stack) {
      _log.w('failed to read media generation', error, stack);
      return _lastGeneration;
    }
  }

  Future<void> _storeGeneration(Map<String, int> generation) async {
    _lastGeneration = Map.of(generation);
    try {
      await (await SharedPreferences.getInstance()).setString(CollectionPagingKeys.mediaGeneration, jsonEncode(generation));
    } catch (error, stack) {
      _log.e('failed to persist media generation', error, stack);
    }
  }
}
