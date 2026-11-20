import 'dart:async';
import 'dart:math';

import 'package:aves/features/batch_ops/db/batch_result_store.dart';
import 'package:aves/features/batch_ops/log.dart';
import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_result_recorder.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/enums.dart';
import 'package:aves/services/media/media_edit_service.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:collection/collection.dart';

/// Records batch results and applies them back to their sources.
///
/// The run itself never touches an original. This service owns the only
/// destructive operations the feature has, and each one is driven by a recorded
/// row: a file in the results folder without a row is never replaced, moved or
/// deleted from here.
class BatchResultsService implements BatchResultRecorder {
  final AppDatabaseProvider? provider;
  final BatchService native;
  final MediaEditService? mediaEdit;
  final LocalMediaDb? db;
  final MediaFetchService? fetch;
  final BatchSettings? batchSettingsOverride;

  const new({
    this.provider,
    this.native = const BatchService(),
    this.mediaEdit,
    this.db,
    this.fetch,
    this.batchSettingsOverride,
  });

  AppDatabaseProvider get _provider => provider ?? getIt<AppDatabaseProvider>();
  MediaEditService get _mediaEditService => mediaEdit ?? mediaEditService;
  LocalMediaDb get _localDb => db ?? localMediaDb;
  MediaFetchService get _fetchService => fetch ?? mediaFetchService;
  BatchSettings get _settings => batchSettingsOverride ?? batchSettings;

  Future<BatchResultStore> store() async => BatchResultStore(await _provider.open());

  /// Absolute path of the results folder on primary storage.
  String get resultsDirectory => pContext.join(androidFileUtils.primaryStorage, batchResultsRelativeRoot);

  // -- recording --------------------------------------------------------------

  @override
  Future<void> record(BatchRecordedItem recorded) async {
    final output = recorded.outputRelativePath;
    final absolute = recorded.resultPath;
    // Copy-share writes elsewhere: only a normal batch run belongs here. The
    // share check comes first so the invariant holds even if the two roots ever
    // overlap (a share root below the results root would match both predicates).
    if (output == null || isBatchShareRelativePath(output)) return;
    if (!isBatchResultsRelativePath(output)) return;
    if (absolute != null && absolute.isNotEmpty && !isBatchResultsPath(absolute)) return;

    await _settings.ensureLoaded();
    final source = await _resolveEntry(recorded.item.uri);
    final fileName = recorded.resultName ?? (absolute != null && absolute.isNotEmpty ? pContext.basename(absolute) : recorded.item.displayName);
    final result = BatchResult(
      id: '${recorded.jobId}-${recorded.index}',
      jobId: recorded.jobId,
      sourceEntryId: recorded.item.entryId,
      sourceUri: recorded.item.uri,
      sourcePath: source?.path ?? '',
      sourceDirectory: source?.directory ?? '',
      sourceName: recorded.item.displayName,
      resultUri: recorded.resultUri,
      resultPath: absolute ?? '',
      resultFileName: fileName,
      resultMimeType: recorded.resultMimeType ?? '',
      resultSizeBytes: recorded.resultSize ?? 0,
      actionsJson: encodeBatchActions(recorded.actions),
      createdAt: DateTime.now(),
      status: BatchResultStatus.pending,
    );

    final resultStore = await store();
    await resultStore.insertResult(result);
    if (_settings.resultMode == BatchResultMode.replacePrevious) {
      await _supersedeOlder(result, resultStore);
    }
    await _pinResultsFolderOnce();
  }

  /// Frees the plain name for [keep] by parking and deleting the result it
  /// supersedes.
  ///
  /// The old file is renamed to `<name>-to-remove` first, so the new result can
  /// take `<name>` without a MediaStore `(1)` suffix; only then is the parked
  /// file deleted. A failure at any step leaves both files in place.
  Future<void> _supersedeOlder(BatchResult keep, BatchResultStore resultStore) async {
    final older = await resultStore.getPendingBySource(keep.sourceUri, exceptId: keep.id);
    if (older.isEmpty) return;

    final base = keep.sourceBaseName;
    final keepExtension = _extensionOf(keep.resultFileName);

    for (final old in older) {
      final entry = await _resolveEntry(old.resultUri);
      if (entry == null) {
        await resultStore.deleteResults([old.id]);
        continue;
      }
      final oldExtension = _extensionOf(old.resultFileName);
      final parkedName = '$base$batchResultSupersededSuffix${oldExtension.isEmpty ? '' : '.$oldExtension'}';
      final parked = await _rename(entry, parkedName) ?? entry;
      final deleted = await native.deleteResult(parked.uri);
      if (!deleted) {
        batchLog.w('failed to delete superseded result ${parked.uri}');
        continue;
      }
      await _localDb.removeIds({parked.id});
      await resultStore.deleteResults([old.id]);
    }

    final desiredName = keepExtension.isEmpty ? base : '$base.$keepExtension';
    final current = await _resolveEntry(keep.resultUri);
    if (current == null) return;
    if (_fileNameOf(current) == desiredName) return;
    final renamed = await _rename(current, desiredName);
    if (renamed == null) return;
    await resultStore.updateResultLocation(
      keep.id,
      uri: renamed.uri,
      path: renamed.path ?? '',
      fileName: _fileNameOf(renamed),
      mimeType: renamed.mimeType,
      sizeBytes: renamed.sizeBytes ?? 0,
    );
  }

  /// Pins the results folder once per install.
  ///
  /// A user who unpins it later is not overruled: the claim marker is written
  /// before the pin, so only the first successful run ever adds it.
  Future<void> _pinResultsFolderOnce() async {
    try {
      if (!await _settings.claimResultsPin()) return;
      final filter = StoredAlbumFilter(resultsDirectory, null);
      settings.pinnedFilters = {...settings.pinnedFilters, filter};
    } catch (error, stack) {
      batchLog.w('failed to pin the batch results folder', error, stack);
    }
  }

  // -- applying ---------------------------------------------------------------

  /// Overwrites each source with its recorded result.
  ///
  /// Returns how many sources were replaced. A result whose replacement failed
  /// stays pending, so the user can retry or move it back instead. Write access
  /// to the sources is requested once, before the first write.
  Future<int> replaceWithSource(Iterable<BatchResult> results) async {
    final targets = results.where((result) => result.canReplaceSource).toList(growable: false);
    if (targets.isEmpty) return 0;
    await _requestWriteAccess(targets);

    final resultStore = await store();
    var replaced = 0;
    for (final result in targets) {
      final ok = await native.replaceWithResult(sourceUri: result.sourceUri, resultUri: result.resultUri);
      if (!ok) continue;
      replaced++;
      await _refreshSource(result);
      await resultStore.deleteResults([result.id]);
    }
    if (replaced > 0) unawaited(reloadPagedSummaries());
    return replaced;
  }

  /// Asks for write access to every source at once.
  ///
  /// The MediaStore caps one request at 2000 URIs, so a larger selection is
  /// chunked. A denial is not treated as a failure: files the app owns can still
  /// be written, and the per-item result reports the rest.
  Future<void> _requestWriteAccess(List<BatchResult> results) async {
    const chunkSize = 2000;
    final mimeByUri = <String, String>{};
    for (final result in results) {
      final entry = await _resolveEntry(result.sourceUri);
      mimeByUri[result.sourceUri] = entry?.mimeType ?? 'image/*';
    }
    final uris = mimeByUri.keys.toList(growable: false);
    for (var start = 0; start < uris.length; start += chunkSize) {
      final chunk = uris.sublist(start, min(start + chunkSize, uris.length));
      await native.requestWriteAccess(uris: chunk, mimeTypes: [for (final uri in chunk) mimeByUri[uri]!]);
    }
  }

  /// Moves each result into the directory its source came from.
  ///
  /// Name conflicts are renamed, never overwritten: this action is the
  /// non-destructive alternative to [replaceWithSource]. Returns how many files
  /// moved.
  Future<int> moveBack(Iterable<BatchResult> results) async {
    final candidates = results.where((result) => result.canMoveBack).toList(growable: false);
    if (candidates.isEmpty) return 0;

    final byDirectory = <String, Set<AvesEntry>>{};
    final resultByUri = <String, BatchResult>{};
    for (final result in candidates) {
      final entry = await _resolveEntry(result.resultUri);
      if (entry == null) continue;
      byDirectory.putIfAbsent(result.sourceDirectory, () => {}).add(entry);
      resultByUri[entry.uri] = result;
    }
    if (byDirectory.isEmpty) return 0;

    final processed = <MoveOpEvent>[];
    await for (final event in _mediaEditService.move(
      opId: _mediaEditService.newOpId,
      entriesByDestination: byDirectory,
      copy: false,
      nameConflictStrategy: NameConflictStrategy.rename,
    )) {
      processed.add(event);
    }
    final success = processed.where((event) => event.success && !event.deleted).toSet();
    if (success.isEmpty) return 0;

    await _syncAfterTransfer(success, byDirectory.values.expand((entries) => entries).toSet(), copy: false);

    final movedUris = success.map((event) => event.uri).toSet();
    final movedRows = resultByUri.entries.where((entry) => movedUris.contains(entry.key)).map((entry) => entry.value).toList(growable: false);
    final resultStore = await store();
    await resultStore.deleteResults(movedRows.map((result) => result.id));
    unawaited(reloadPagedSummaries());
    return movedRows.length;
  }

  /// Points the app's rows at what the native operation changed.
  ///
  /// The MediaStore is already updated; without this, a moved result would keep
  /// serving a path that no longer exists and a replaced source would keep its
  /// old size and name.
  Future<void> _syncAfterTransfer(Set<MoveOpEvent> ops, Set<AvesEntry> sources, {required bool copy}) async {
    final byUri = {for (final entry in sources) entry.uri: entry};
    final inserts = <AvesEntry>{};
    final updates = <int, AvesEntry>{};
    final removals = <int>{};
    for (final op in ops) {
      final newUri = op.newFields['uri'] as String?;
      if (newUri == null) continue;
      AvesEntry? entry;
      try {
        entry = await _fetchService.getEntry(newUri, null);
      } catch (error, stack) {
        batchLog.w('failed to read the transferred entry $newUri', error, stack);
      }
      if (entry == null) continue;
      final source = byUri[op.uri];
      if (!copy && source != null && source.uri == newUri) {
        // The volume kept the id and only the path or name changed.
        entry.id = source.id;
        updates[source.id] = entry;
        continue;
      }
      entry
        ..origin = EntryOrigins.mediaStoreContent
        ..id = _localDb.nextId;
      inserts.add(entry);
      if (!copy && source != null) removals.add(source.id);
    }
    for (final update in updates.entries) {
      await _localDb.updateEntry(update.key, update.value);
    }
    if (inserts.isNotEmpty) {
      await _localDb.insertEntries(inserts);
    }
    if (removals.isNotEmpty) {
      await _localDb.removeIds(removals);
    }
  }

  Future<void> _refreshSource(BatchResult result) async {
    final fresh = await _fetchService.getEntry(result.sourceUri, null);
    if (fresh == null) return;
    final local = await _localDb.loadEntriesByUris({result.sourceUri});
    final existing = local.firstOrNull;
    if (existing != null) {
      fresh.id = existing.id;
      await _localDb.updateEntry(existing.id, fresh);
      return;
    }
    if (result.sourceEntryId != null) {
      fresh.id = result.sourceEntryId!;
      await _localDb.updateEntry(result.sourceEntryId!, fresh);
      return;
    }
    fresh
      ..origin = EntryOrigins.mediaStoreContent
      ..id = _localDb.nextId;
    await _localDb.insertEntries({fresh});
  }

  // -- housekeeping -----------------------------------------------------------

  /// Forgets rows whose result file no longer exists.
  ///
  /// Deleting a result from the album is normal browsing, so the row must not
  /// keep offering "replace the original" for a file that is gone. Existence is
  /// asked from the MediaStore, not from the app's table, so a freshly written
  /// result the scanner has not indexed yet is not mistaken for a missing one.
  Future<int> pruneMissingResults() async {
    final resultStore = await store();
    final pending = await resultStore.getPending();
    if (pending.isEmpty) return 0;

    // The app's table already answers for every file the scanner imported; only
    // a row it does not know yet (written seconds ago) needs a platform query.
    final uris = pending.map((result) => result.resultUri).toSet();
    final known = (await _localDb.loadEntriesByUris(uris)).map((entry) => entry.uri).toSet();
    final missing = <String>[];
    for (final result in pending) {
      if (known.contains(result.resultUri)) continue;
      if (!await _entryExists(result.resultUri)) missing.add(result.id);
    }
    if (missing.isEmpty) return 0;
    await resultStore.deleteResults(missing);
    return missing.length;
  }

  /// Removes parked `-to-remove` files left behind by an interrupted cleanup.
  ///
  /// They are rows in the results folder, so they are found from the app's own
  /// entry table rather than by walking storage.
  Future<int> pruneSupersededFiles() async {
    final entries = await _localDb.loadEntries(directory: resultsDirectory);
    final leftovers = entries.where((entry) => _fileNameOf(entry).toLowerCase().contains(batchResultSupersededSuffix)).toList(growable: false);
    if (leftovers.isEmpty) return 0;
    var removed = 0;
    for (final entry in leftovers) {
      if (!await native.deleteResult(entry.uri)) continue;
      removed++;
      await _localDb.removeIds({entry.id});
    }
    return removed;
  }

  // -- lookups ----------------------------------------------------------------

  Future<AvesEntry?> _resolveEntry(String uri) async {
    if (uri.isEmpty) return null;
    try {
      final local = await _localDb.loadEntriesByUris({uri});
      final hit = local.firstOrNull;
      if (hit != null) return hit;
    } catch (error, stack) {
      batchLog.w('failed to look up $uri locally', error, stack);
    }
    try {
      return await _fetchService.getEntry(uri, null);
    } catch (error, stack) {
      batchLog.w('failed to read entry $uri', error, stack);
      return null;
    }
  }

  Future<bool> _entryExists(String uri) async {
    if (uri.isEmpty) return false;
    try {
      return await _fetchService.getEntry(uri, null) != null;
    } catch (_) {
      return false;
    }
  }

  Future<AvesEntry?> _rename(AvesEntry entry, String name) async {
    final ops = await _mediaEditService.rename(opId: _mediaEditService.newOpId, entriesToNewName: {entry: name}).toList();
    final op = ops.where((event) => event.success && !event.deleted).firstOrNull;
    if (op == null) return null;
    await _syncAfterTransfer({op}, {entry}, copy: false);
    final newUri = op.newFields['uri'] as String? ?? entry.uri;
    return _resolveEntry(newUri);
  }

  String _fileNameOf(AvesEntry entry) {
    final path = entry.path;
    if (path != null && path.isNotEmpty) return pContext.basename(path);
    return entry.bestTitle ?? '';
  }

  String _extensionOf(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index <= 0 || index == fileName.length - 1 ? '' : fileName.substring(index + 1);
  }
}

const batchResultsService = BatchResultsService();
