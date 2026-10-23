import 'dart:async';
import 'dart:convert';

import 'package:aves/features/collection_paging/engine/collection_paging_keys.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/sync/platform_timeout.dart';
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
///   when the generation moved, only the changed URIs are fetched, and the
///   vanished ones are settled by one obsolete-check for the whole set.
/// - [importAll]: chunked full scan for a first launch on an unseen library
///   (or an interrupted one). Streams every row once, upserts per chunk by
///   content id, and skips rows already in the database — so reruns resume
///   instead of duplicating, at any scale.
///
/// The generation cursor persists in `SharedPreferences`, so restarts do not
/// redownload the world.
class PagedDiscoverer {
  /// How long the import stream may stay silent before it is treated as dead.
  ///
  /// The platform stream has no deadline of its own: a reply lost while the
  /// engine restarts leaves it neither emitting nor closing, so the first batch
  /// never lands and the failure path is unreachable. A real scan emits rows
  /// continuously; a gap this long is a broken stream, not a slow library.
  static const importStreamIdleTimeout = Duration(seconds: 30);

  final MediaStoreService mediaStore;
  final MediaFetchService mediaFetch;
  final LocalMediaDb database;
  final Future<void> Function(AvesEntry entry) catalogEntry;
  final Duration streamIdleTimeout;

  /// Upper bound on the failed URIs kept for a later retry.
  ///
  /// A bulk failure is better retried as a whole: the generation cursor is kept,
  /// so the next sync reads the same change set again, instead of writing an
  /// unbounded list to preferences.
  static const int maxPendingUris = 5000;

  Map<String, int>? _lastGeneration;
  Set<String>? _pendingUris;
  bool _importing = false;
  new({
    MediaStoreService? mediaStore,
    MediaFetchService? mediaFetch,
    LocalMediaDb? database,
    Future<void> Function(AvesEntry entry)? catalogEntry,
    this.streamIdleTimeout = importStreamIdleTimeout,
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

  /// URIs a failed sync still owes, for tests.
  @visibleForTesting
  Set<String>? get pendingUris => _pendingUris;

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
    // A URI that failed earlier changed before the cursor the sync stored, so
    // the generation alone would never offer it again.
    final pending = await _readPendingUris();
    if (_equalGenerations(since, generation) && pending.isEmpty) return 0;
    final result = await _syncChanged(since, pending);
    if (result.failed.length > maxPendingUris) {
      // Too many to carry: keep the old cursor so the next sync re-reads the
      // whole change set, and leave the previously persisted list in place.
      _log.w('paged sync could not settle ${result.failed.length} uris, keeping the generation for a full retry');
      return result.applied;
    }
    // The retry list has to be on disk before the cursor moves past it: the
    // writes are not atomic, and a process death in between would leave the
    // change behind a cursor that will never offer it again (see
    // [_readPendingUris]). Nothing is lost if the cursor stays put instead: the
    // change set is read again, and applying it twice is idempotent.
    if (!await _storePendingUris(result.failed)) {
      _log.w('paged sync could not persist the retry list, keeping the generation for a full retry');
      return result.applied;
    }
    await _storeGeneration(generation);
    return result.applied;
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
    // The cursor is taken before the scan, not after it: the stream is ordered
    // newest first, so a file that changes while the scan runs is behind the
    // rows it has already passed, and a cursor read at the end would claim that
    // change had been applied. The request goes out with the first row and is
    // awaited with the last, so a slow ack delays the completion, not the
    // first paint. Nothing is lost if it never answers: the cursor the
    // bootstrap stored stays, and the next sync re-reads the change set (the
    // import is idempotent).
    final generationFuture = withPlatformTimeout(mediaStore.getGenerationByVolume, label: 'media store generation');
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

      // A lost platform reply leaves the stream neither emitting nor closing,
      // which used to pin the first import forever: no first batch, no error,
      // no retry. Bound the silence so it becomes a failure the caller can
      // report and the user can retry.
      final stream = StreamIterator(mediaStore.getEntries(const {}));
      try {
        while (true) {
          final bool hasNext;
          try {
            hasNext = await stream.moveNext().timeout(streamIdleTimeout);
          } on TimeoutException {
            _log.w('paged import stream stalled for ${streamIdleTimeout.inSeconds}s');
            throw TimeoutException('paged import stream stalled', streamIdleTimeout);
          }
          if (!hasNext) break;
          final entry = stream.current;
          entry.id = database.nextId;
          batch.add(entry);
          if (!signalled) {
            if (batch.length >= firstBatchLimit) await signalFirstBatch();
          } else if (batch.length >= 2000) {
            await flush();
          }
        }
      } finally {
        await stream.cancel();
      }
      await signalFirstBatch();
      await flush();

      // A retry list from before this run is deliberately left in place: the
      // import upserts but never deletes, so an entry can still be the only
      // record of a row the media store no longer serves. The next sync settles
      // those instead of dropping them with the list.
      //
      // The cursor is the one captured before the scan; a completed import is
      // resumable and writes by content id, so re-reading a change costs one
      // row, whereas a cursor past it would lose the file for good.
      final generation = await generationFuture;
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

  /// A content id the database can key a row by.
  ///
  /// MediaStore ids are positive. A provider that reports none may still hand
  /// back 0, and two such rows would collapse into one map entry (and one
  /// insert). Those rows are identified by URI instead.
  static int? _usableContentId(int? contentId) => contentId != null && contentId > 0 ? contentId : null;

  /// The newer of two rows that share an identity, [a] on a tie.
  static AvesEntry _newest(AvesEntry a, AvesEntry b) => (b.dateModifiedMillis ?? 0) > (a.dateModifiedMillis ?? 0) ? b : a;

  /// The surviving report of one file, keeping the identity either report
  /// carried.
  ///
  /// A provider can repeat a row, and the repeat may be the only report that
  /// names a content id: dropping it would store the file without an id, and the
  /// next pass would take the URI-only path for a row that has one.
  static AvesEntry _merge(AvesEntry a, AvesEntry b) {
    final newest = _newest(a, b);
    final other = identical(newest, a) ? b : a;
    newest.contentId ??= _usableContentId(other.contentId);
    return newest;
  }

  /// Applies one batch: existing rows (by content id) are overwritten when
  /// modified, missing rows are inserted, trash details are attached.
  /// Returns the number of written rows.
  Future<int> _upsertBatch(Set<AvesEntry> batch) async {
    if (batch.isEmpty) return 0;
    // One file must never enter the database twice, whichever identity the
    // provider reported it under. The stream is ordered newest first, but a
    // provider can repeat a row, and the repeat can arrive with the content id
    // the first report lacked: keyed separately by id and by URI, the two
    // reports each took their own identity to the insert (there is no unique
    // index on the URI to stop them). Merging by URI first leaves one report per
    // file, so the identity maps below cannot both write it.
    final byUri = <String, AvesEntry>{};
    for (final entry in batch) {
      entry.contentId = _usableContentId(entry.contentId);
      byUri.update(entry.uri, (v) => _merge(v, entry), ifAbsent: () => entry);
    }
    final byContentId = <int, AvesEntry>{};
    final uriOnly = <String, AvesEntry>{};
    for (final entry in byUri.values) {
      final contentId = entry.contentId;
      if (contentId != null) {
        byContentId.update(contentId, (v) => _newest(v, entry), ifAbsent: () => entry);
      } else {
        uriOnly[entry.uri] = entry;
      }
    }
    final knownByContentId = {
      for (final entry in await database.loadEntriesByContentIds(byContentId.keys.toSet())) entry.contentId: entry,
    };
    final knownByUri = uriOnly.isEmpty
        ? <String, AvesEntry>{}
        : {
            for (final entry in await database.loadEntriesByUris(uriOnly.keys.toSet()))
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
      // Matching by URI is a fallback for a provider that reports no id, not a
      // reason to forget the id the row already had.
      entry.contentId ??= _usableContentId(knownEntry.contentId);
      entry.id = knownEntry.id;
      await database.updateEntry(knownEntry.id, entry);
      await _saveTrash(entry);
      written++;
    }

    for (final kv in byContentId.entries) {
      await upsert(kv.value, knownByContentId[kv.key]);
    }
    for (final kv in uriOnly.entries) {
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

  /// Syncs exactly the URIs changed since [sinceGeneration], plus [pending]
  /// URIs a previous run could not settle.
  Future<({int applied, Set<String> failed})> _syncChanged(Map<String, int> sinceGeneration, Set<String> pending) async {
    final changedUris = {...await mediaStore.getChangedUris(sinceGeneration), ...pending};
    if (changedUris.isEmpty) return (applied: 0, failed: <String>{});
    var applied = 0;
    final failed = <String>{};
    // The URIs the platform no longer serves are settled together, after the
    // reads: the obsolete check scans the whole media store, so asking it per
    // URI made a bulk delete cost one full scan per file.
    final vanished = <String>{};
    for (final uri in changedUris) {
      try {
        final entry = await mediaFetch.getEntry(uri, null);
        if (entry == null) {
          vanished.add(uri);
        } else if (await _syncFetchedEntry(uri, entry)) {
          applied++;
        }
      } catch (error, stack) {
        // The generation cursor must not move past this row: hand the URI to
        // the next sync instead of dropping the change.
        failed.add(uri);
        _log.w('paged sync failed for uri=$uri (will retry)', error, stack);
      }
      // Cooperative yield between platform round-trips.
      await Future<void>.delayed(Duration.zero);
    }
    try {
      applied += await _removeObsoleteUris(vanished);
    } catch (error, stack) {
      failed.addAll(vanished);
      _log.w('paged sync failed to remove ${vanished.length} obsolete uris (will retry)', error, stack);
    }
    return (applied: applied, failed: failed);
  }

  /// Returns true when [entry] produced a database write.
  Future<bool> _syncFetchedEntry(String uri, AvesEntry entry) async {
    final contentId = _usableContentId(entry.contentId);
    entry.contentId = contentId;
    entry.origin = EntryOrigins.mediaStoreContent;
    var existing = contentId == null ? null : (await database.loadEntriesByContentIds({contentId})).firstOrNull;
    // A row stored without a content id (or before the provider reported one)
    // is still the same row: match it by URI before inserting a duplicate.
    existing ??= await _mediaStoreRowByUri(uri);
    if (existing != null) {
      if ((entry.dateModifiedMillis ?? 0) <= (existing.dateModifiedMillis ?? 0) && existing.path == entry.path) return false;
      // Matching by URI is a fallback for a provider that reports no id, not a
      // reason to forget the id the row already had.
      entry.contentId ??= _usableContentId(existing.contentId);
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
    entry.id = database.nextId;
    try {
      await catalogEntry(entry);
    } catch (error, stack) {
      _log.w('paged sync catalog failed for uri=$uri', error, stack);
    }
    await database.insertEntries({entry});
    await _saveTrash(entry);
    return true;
  }

  /// The media-store row stored for [uri], ignoring a vault row that shares it.
  Future<AvesEntry?> _mediaStoreRowByUri(String uri) async => (await database.loadEntriesByUris({uri})).where((row) => row.origin == EntryOrigins.mediaStoreContent).firstOrNull;

  /// The content id encoded in a media URI, if it ends with one.
  static int? _contentIdOfUri(String uri) {
    final contentId = int.tryParse(Uri.parse(uri).pathSegments.lastOrNull ?? '');
    return contentId != null && contentId > 0 ? contentId : null;
  }

  /// Removes the rows for the URIs MediaStore no longer serves, returning how
  /// many went.
  ///
  /// Ids are not reuse-proof: a provider can hand a deleted row's id to a new
  /// file, so a still-live id is compared by path before its row is kept —a
  /// number that came back is not proof that the file did. A row stored without
  /// an id has nothing but its URI, and `getEntry` already reported that the
  /// media store does not serve it anymore.
  Future<int> _removeObsoleteUris(Set<String> uris) async {
    if (uris.isEmpty) return 0;
    final urisByContentId = <int, String>{};
    final uriOnly = <String>{};
    for (final uri in uris) {
      final contentId = _contentIdOfUri(uri);
      if (contentId != null) {
        urisByContentId[contentId] = uri;
      } else {
        uriOnly.add(uri);
      }
    }

    // Candidates from both identities: a row may carry the id, may have been
    // stored without one, or may carry an id the provider stopped reporting.
    final rowsByUri = <String, List<AvesEntry>>{};
    for (final row in await database.loadEntriesByUris({...uriOnly, ...urisByContentId.values})) {
      // Restricted to media-store rows so a vault row sharing the URI survives.
      if (row.origin != EntryOrigins.mediaStoreContent) continue;
      (rowsByUri[row.uri] ??= []).add(row);
    }
    final rowsById = <int, List<AvesEntry>>{};
    if (urisByContentId.isNotEmpty) {
      for (final row in await database.loadEntriesByContentIds(urisByContentId.keys.toSet())) {
        final contentId = row.contentId;
        if (contentId != null) (rowsById[contentId] ??= []).add(row);
      }
    }

    final obsolete = urisByContentId.isEmpty ? const <int>{} : (await mediaStore.checkObsoleteContentIds(urisByContentId.keys.toList())).toSet();
    final liveIds = urisByContentId.keys.whereNot(obsolete.contains);
    // The stored path is what a live id has to match to still be this row.
    final pathById = <int, String>{};
    for (final contentId in liveIds) {
      final path = [...?rowsById[contentId], ...?rowsByUri[urisByContentId[contentId]]].map((v) => v.path).whereType<String>().firstOrNull;
      if (path != null) pathById[contentId] = path;
    }
    final staleIds = pathById.isEmpty ? const <int>{} : (await mediaStore.checkObsoletePaths(pathById)).toSet();

    final doomed = <int, AvesEntry>{};
    void forget(Iterable<AvesEntry> rows) {
      for (final row in rows) {
        doomed[row.id] = row;
      }
    }

    for (final contentId in {...obsolete, ...staleIds}) {
      forget(rowsById[contentId] ?? const []);
      final uri = urisByContentId[contentId];
      if (uri != null) forget(rowsByUri[uri] ?? const []);
    }
    for (final uri in uriOnly) {
      forget(rowsByUri[uri] ?? const []);
    }
    if (doomed.isEmpty) return 0;
    await database.removeIds(doomed.keys.toSet());
    return doomed.length;
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

  Future<Set<String>> _readPendingUris() async {
    final cached = _pendingUris;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(CollectionPagingKeys.pendingSyncUris);
      if (raw == null || raw.isEmpty) return _pendingUris = {};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _pendingUris = {};
      return _pendingUris = decoded.whereType<String>().toSet();
    } catch (error, stack) {
      _log.w('failed to read pending sync uris', error, stack);
      return _pendingUris = {};
    }
  }

  /// Persists [uris] as the changes the next sync still owes.
  ///
  /// Returns whether the platform accepted the write: the caller must not move
  /// the generation cursor past a retry list it could not store.
  Future<bool> _storePendingUris(Set<String> uris) async {
    _pendingUris = Set.of(uris);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = uris.isEmpty ? await prefs.remove(CollectionPagingKeys.pendingSyncUris) : await prefs.setString(CollectionPagingKeys.pendingSyncUris, jsonEncode(uris.toList()));
      if (!stored) _log.w('pending sync uris were not persisted');
      return stored;
    } catch (error, stack) {
      _log.e('failed to persist pending sync uris', error, stack);
      return false;
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
