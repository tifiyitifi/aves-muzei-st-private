import 'dart:async';

import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/refra_edit/db/refra_edit_store.dart';
import 'package:aves/features/refra_edit/log.dart';
import 'package:aves/features/refra_edit/model/refra_edit_paths.dart';
import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/enums.dart';
import 'package:collection/collection.dart';

/// A record and the media entry it resolves to, for thumbnails and the viewer.
typedef RefraEditRecordItem = ({RefraEditRecord record, AvesEntry? entry});

/// Copy-first editing.
///
/// Every session copies the source into `Pictures/aves_refra_edit` and only ever edits that copy:
/// the built-in editor and third-party editors both receive the staged uri, so an OEM editor that
/// overwrites its input cannot destroy the user's original. The session row remembers the source
/// directory, which is the only destination the copies can be moved back to.
///
/// All sessions share that one folder, so the album list gets a single edit album instead of one
/// per session. Which files belong to which session is answered by the database: a session records
/// the folder contents before and after its editor runs, and the difference is its result set.
class RefraEditService {
  static const _editChannel = AvesMethodChannel('deckers.thibault/aves/media_edit');

  final AppDatabaseProvider? provider;

  const new({this.provider});

  AppDatabaseProvider get _provider => provider ?? getIt<AppDatabaseProvider>();

  Future<RefraEditStore> _store() async => RefraEditStore(await _provider.open());

  static String newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<RefraEditStore> store() => _store();

  /// Absolute staging directory shared by every session.
  Future<String> stagingDirectory() async {
    final result = await _editChannel.invokeMethod('refraStagingDir', const <String, Object?>{});
    if (result is! String || result.isEmpty) {
      throw StateError('Cannot resolve the editor staging directory');
    }
    return result;
  }

  /// Copies [source] into the staging directory and records the session.
  ///
  /// A source that already lives in the staging tree is rejected: copying it again would
  /// manufacture a copy of a copy and lose the folder the user actually edits from.
  Future<RefraEditSession> createSession(AvesEntry source) async {
    if (isRefraEditStagingPath(source.directory ?? '')) {
      throw StateError('${source.uri} already lives in the edit staging tree');
    }

    final sessionId = newSessionId();
    final stagingDir = await stagingDirectory();

    MoveOpEvent? copied;
    await for (final event in mediaEditService.move(
      opId: mediaEditService.newOpId,
      entriesByDestination: {
        stagingDir: [source],
      },
      copy: true,
      nameConflictStrategy: NameConflictStrategy.rename,
    )) {
      if (event.success && event.newFields['uri'] is String) {
        copied = event;
      }
    }
    if (copied == null) {
      throw StateError('Copying ${source.uri} into $stagingDir failed');
    }

    final stagedUri = copied.newFields['uri'] as String;
    final stagedPath = (copied.newFields['path'] as String?) ?? '';
    final sourcePath = source.path ?? '';
    final fileName = sourcePath.isNotEmpty ? pContext.basename(sourcePath) : Uri.parse(source.uri).pathSegments.last;
    final session = RefraEditSession(
      id: sessionId,
      sourceEntryId: source.id,
      sourceUri: source.uri,
      sourcePath: sourcePath,
      sourceDirectory: source.directory ?? '',
      sourceName: fileName,
      sourceMimeType: source.mimeType,
      stagingDirectory: stagingDir,
      stagedUri: stagedUri,
      createdAt: DateTime.now(),
      status: RefraEditSessionStatus.active,
    );

    final store = await _store();
    await store.insertSession(session);
    await store.addOutput(
      RefraEditOutput(
        id: '$sessionId-0',
        sessionId: sessionId,
        uri: stagedUri,
        path: stagedPath,
        fileName: stagedPath.isNotEmpty ? pContext.basename(stagedPath) : fileName,
        kind: RefraEditOutputKind.staged,
        sizeBytes: source.sizeBytes ?? 0,
        createdAt: DateTime.now(),
      ),
    );
    await _ensureEntries({stagedUri});
    unawaited(reloadPagedSummaries());
    return session;
  }

  /// Opens the built-in editor on the session's staged copy.
  ///
  /// Returns true when the editor reported a save; false on cancel or failure. A cancelled run
  /// that produced nothing drops its copy instead of leaving it behind.
  Future<bool> openBuiltIn(RefraEditSession session) async {
    final before = await _folderUris();
    final result = await appService.refraEdit(session.stagedUri, refraEditStagingRelativeRoot);
    await _recordNewOutputs(session, before, RefraEditOutputKind.builtIn);
    final error = result['error'] as String?;
    if (error != null) {
      refraEditLog.w('built-in editor failed: $error');
      await _dropUneditedCopy(session);
      return false;
    }
    return true;
  }

  /// Opens the system editor chooser on the session's staged copy.
  ///
  /// Returns true when a third-party editor reported a result; its files are found by comparing
  /// the folder before and after, because an external app gives no reliable list of written files.
  /// A cancelled run that produced nothing drops its copy instead of leaving it behind.
  Future<bool> openExternal(RefraEditSession session) async {
    final before = await _folderUris();
    final fields = await appService.edit(session.stagedUri, session.sourceMimeType);
    await _recordNewOutputs(session, before, RefraEditOutputKind.external);
    if (fields['error'] != null) {
      await _dropUneditedCopy(session);
      return false;
    }
    return true;
  }

  /// Drops the staged copy of a session the user cancelled before producing anything.
  ///
  /// The copy only existed for the editor run that just ended, so keeping it would leave an
  /// unedited duplicate in `Pictures/aves_refra_edit` for every cancelled edit.
  Future<void> _dropUneditedCopy(RefraEditSession session) async {
    final outputs = await (await _store()).getOutputs(session.id);
    if (outputs.length != 1 || outputs.single.kind != RefraEditOutputKind.staged) return;
    await discard(session);
  }

  /// Reconciles the recorded outputs with Aves' database and returns them, one entry per file.
  ///
  /// The files are catalogued here because the editor writes outside the collection pipeline:
  /// without a database row a copy has no album, cannot be opened from the session page and cannot
  /// be moved back.
  Future<List<RefraEditOutput>> refreshOutputs(RefraEditSession session) async {
    final store = await _store();
    final outputs = await store.getOutputs(session.id);
    if (await _ensureEntries(outputs.map((o) => o.uri).toSet())) {
      unawaited(reloadPagedSummaries());
    }
    return _uniqueOutputs(outputs);
  }

  /// Collapses rows that describe the same file under different volume aliases.
  ///
  /// Rows written before the scanner was aligned with the move operation can hold the same file
  /// twice. They are kept (dropping them would destroy history the user did not ask to lose) but
  /// only listed and transferred once.
  static List<RefraEditOutput> _uniqueOutputs(Iterable<RefraEditOutput> outputs) {
    final seen = <String>{};
    return [
      for (final output in outputs)
        if (seen.add(_outputKey(output))) output,
    ];
  }

  static String _outputKey(RefraEditOutput output) => refraEditFileKey(
    path: output.path,
    uri: output.uri,
    fileName: output.fileName,
    sizeBytes: output.sizeBytes,
  );

  static String? _entryFileName(AvesEntry entry) {
    final path = entry.path;
    return path == null ? null : pContext.basename(path);
  }

  static String _entryKey(AvesEntry entry) {
    final path = entry.path ?? '';
    return refraEditFileKey(
      path: path,
      uri: entry.uri,
      fileName: path.isNotEmpty ? pContext.basename(path) : '',
      sizeBytes: entry.sizeBytes ?? 0,
    );
  }

  Future<void> _recordNewOutputs(
    RefraEditSession session,
    Map<String, _StagedFile> before,
    RefraEditOutputKind kind,
  ) async {
    final after = await _folderUris();
    final added = after.keys.where((key) => !before.containsKey(key)).toList();
    if (added.isEmpty) return;
    final store = await _store();
    final knownKeys = (await store.getOutputs(session.id)).map(_outputKey).toSet();
    final addedUris = <String>{};
    for (final key in added) {
      if (knownKeys.contains(key)) continue;
      final file = after[key]!;
      addedUris.add(file.uri);
      await store.addOutput(
        RefraEditOutput(
          id: '${session.id}-${DateTime.now().microsecondsSinceEpoch}',
          sessionId: session.id,
          uri: file.uri,
          path: '',
          fileName: file.name,
          kind: kind,
          sizeBytes: file.sizeBytes,
          createdAt: DateTime.now(),
        ),
      );
    }
    if (await _ensureEntries(addedUris)) {
      unawaited(reloadPagedSummaries());
    }
  }

  /// Every media file currently in the staging folder, keyed by [refraEditFileKey].
  Future<Map<String, _StagedFile>> _folderUris() async {
    final result = await _editChannel.invokeMethod('refraListOutputs', <String, Object?>{
      'relativePath': refraEditStagingRelativeRoot,
      'directory': await stagingDirectory(),
    });
    final files = <String, _StagedFile>{};
    if (result is List) {
      for (final raw in result) {
        if (raw is! Map) continue;
        final uri = raw['uri'] as String?;
        if (uri == null) continue;
        final name = (raw['name'] as String?) ?? Uri.parse(uri).pathSegments.last;
        final sizeBytes = (raw['size'] as num?)?.toInt() ?? 0;
        files[refraEditFileKey(path: '', uri: uri, fileName: name, sizeBytes: sizeBytes)] = (uri: uri, name: name, sizeBytes: sizeBytes);
      }
    }
    return files;
  }

  /// Adds the rows of [uris] to Aves' database when they are missing. Returns true on any insert.
  Future<bool> _ensureEntries(Set<String> uris) async {
    if (uris.isEmpty) return false;
    final known = (await localMediaDb.loadEntriesByUris(uris)).where((entry) => entry.origin == EntryOrigins.mediaStoreContent).map((entry) => entry.uri).toSet();
    final missing = uris.difference(known);
    if (missing.isEmpty) return false;
    for (final uri in missing) {
      try {
        final entry = await mediaFetchService.getEntry(uri, null);
        if (entry == null) {
          refraEditLog.w('no media entry for $uri');
          continue;
        }
        entry
          ..origin = EntryOrigins.mediaStoreContent
          ..id = localMediaDb.nextId;
        await localMediaDb.insertEntries({entry});
      } catch (error, stack) {
        refraEditLog.w('failed to record $uri in the media database', error, stack);
      }
    }
    return true;
  }

  // -- records -----------------------------------------------------------------

  /// Every file the editor still holds, newest first, with its media entry when it resolves.
  ///
  /// The page is database-driven on purpose: these are the files the app can still act on, and a
  /// stray file nobody recorded is not an edit result the user asked to manage here.
  Future<List<RefraEditRecordItem>> records() async {
    final store = await _store();
    final sessions = {for (final session in await store.getSessions()) session.id: session};
    final grouped = <String, List<RefraEditOutput>>{};
    for (final output in await store.getAllOutputs()) {
      grouped.putIfAbsent(_outputKey(output), () => []).add(output);
    }

    final records = <RefraEditRecord>[];
    for (final entry in grouped.entries) {
      final rows = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final first = rows.first;
      records.add(
        RefraEditRecord(
          key: entry.key,
          rowIds: rows.map((row) => row.id).toSet(),
          sessionId: first.sessionId,
          uri: first.uri,
          fileName: first.fileName,
          kind: first.kind,
          sizeBytes: first.sizeBytes,
          createdAt: first.createdAt,
          session: sessions[first.sessionId],
        ),
      );
    }
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final uris = records.map((record) => record.uri).toSet();
    if (await _ensureEntries(uris)) {
      unawaited(reloadPagedSummaries());
    }
    final entries = await localMediaDb.loadEntriesByUris(uris);
    final byUri = {for (final entry in entries) entry.uri: entry};
    return [
      for (final record in records) (record: record, entry: byUri[record.uri]),
    ];
  }

  /// Deletes the files behind [records] and forgets their rows.
  ///
  /// Sessions whose last file is gone are dropped with them; a session that still holds other
  /// results survives. Returns true when every file was deleted.
  Future<bool> deleteRecords(Iterable<RefraEditRecord> records) async {
    final list = records.toList(growable: false);
    if (list.isEmpty) return false;
    final entries = await localMediaDb.loadEntriesByUris(list.map((record) => record.uri).toSet());
    if (entries.isNotEmpty) {
      var success = true;
      await for (final event in mediaEditService.delete(
        opId: mediaEditService.newOpId,
        entries: entries,
      )) {
        if (!event.success) success = false;
      }
      if (!success) return false;
      await localMediaDb.removeIds(entries.map((entry) => entry.id).toSet());
    }

    final store = await _store();
    await store.deleteOutputs(list.expand((record) => record.rowIds));
    await store.deleteSessionsWithoutOutputs();
    unawaited(reloadPagedSummaries());
    return true;
  }

  /// Deletes every recorded file and forgets every session.
  ///
  /// Only what the database knows is touched: a leftover file the app never recorded is not an
  /// edit result, so clearing the records leaves it alone.
  Future<bool> clearRecords() async {
    final items = await records();
    if (items.isNotEmpty && !await deleteRecords(items.map((item) => item.record))) return false;
    await (await _store()).clearAll();
    unawaited(reloadPagedSummaries());
    return true;
  }

  /// File names in [directory] that [fileNames] would collide with.
  ///
  /// Compared on the full name: writing `IMG_1.jpg` over `IMG_1.png` is not a conflict.
  Future<Set<String>> conflictingNames(String directory, Iterable<String> fileNames) async {
    if (directory.isEmpty) return {};
    final existing = await localMediaDb.loadEntries(directory: directory);
    final names = existing.map(_entryFileName).whereType<String>().toSet();
    return fileNames.where(names.contains).toSet();
  }

  // -- transfer ----------------------------------------------------------------

  /// Moves or copies the session's outputs back to the directory the source came from.
  ///
  /// [outputKeys] limits the transfer to those files, identified by [refraEditFileKey]; null
  /// transfers everything the session holds. The caller resolves conflicts (replace / rename)
  /// before calling this, so an overwrite is always an explicit user decision. Only files that
  /// actually sit in the staging tree can be transferred, and only towards a source directory
  /// outside it.
  Future<bool> transferBack(
    RefraEditSession session, {
    Iterable<String>? outputKeys,
    required bool copy,
    required NameConflictStrategy nameConflictStrategy,
  }) async {
    final destination = session.sourceDirectory;
    if (destination.isEmpty || isRefraEditStagingPath(destination)) return false;

    final all = await refreshOutputs(session);
    final chosen = outputKeys == null ? all : all.where((output) => outputKeys.contains(_outputKey(output))).toList(growable: false);
    if (chosen.isEmpty) return false;

    final entries = await localMediaDb.loadEntriesByUris(chosen.map((output) => output.uri).toSet());
    final distinct = <String, AvesEntry>{};
    for (final entry in entries) {
      distinct.putIfAbsent(_entryKey(entry), () => entry);
    }
    // The staging tree is the only source this feature may empty.
    if (distinct.isEmpty || !distinct.values.every((entry) => isRefraEditStagingPath(entry.directory ?? ''))) return false;

    final processed = <MoveOpEvent>[];
    await for (final event in mediaEditService.move(
      opId: mediaEditService.newOpId,
      entriesByDestination: {destination: distinct.values.toSet()},
      copy: copy,
      nameConflictStrategy: nameConflictStrategy,
    )) {
      processed.add(event);
    }
    final successOps = processed.where((event) => event.success && !event.deleted).toSet();
    if (successOps.isEmpty) return false;

    await _syncAfterTransfer(successOps: successOps, sources: distinct.values.toSet(), copy: copy);

    final store = await _store();
    if (copy) {
      await store.setSessionStatus(session.id, RefraEditSessionStatus.copied);
    } else {
      final movedKeys = successOps
          .map((event) => distinct.values.firstWhereOrNull((entry) => entry.uri == event.uri))
          .nonNulls
          .map(_entryKey)
          .toSet();
      final remaining = await store.getOutputs(session.id);
      await store.deleteOutputs(remaining.where((output) => movedKeys.contains(_outputKey(output))).map((output) => output.id));
      if ((await store.getOutputs(session.id)).isEmpty) {
        await store.setSessionStatus(session.id, RefraEditSessionStatus.moved);
      }
    }
    unawaited(reloadPagedSummaries());
    return processed.every((event) => event.success);
  }

  /// Points Aves' database at where the transferred files landed.
  ///
  /// The operation already updated the Media Store, but Aves keeps its own rows: a moved file's
  /// staging row would otherwise keep serving a path that no longer exists, and a copied file
  /// would have no row at all.
  Future<void> _syncAfterTransfer({
    required Set<MoveOpEvent> successOps,
    required Set<AvesEntry> sources,
    required bool copy,
  }) async {
    final byUri = {for (final entry in sources) entry.uri: entry};
    final inserts = <AvesEntry>{};
    final updates = <int, AvesEntry>{};
    final removals = <int>{};
    for (final op in successOps) {
      final newUri = op.newFields['uri'] as String?;
      if (newUri == null) continue;
      AvesEntry? entry;
      try {
        entry = await mediaFetchService.getEntry(newUri, null);
      } catch (error, stack) {
        refraEditLog.w('failed to read the transferred entry $newUri', error, stack);
      }
      if (entry == null) continue;
      final source = byUri[op.uri];
      if (!copy && source != null && source.uri == newUri) {
        // The volume kept the id and only the path changed.
        entry.id = source.id;
        updates[source.id] = entry;
        continue;
      }
      entry
        ..origin = EntryOrigins.mediaStoreContent
        ..id = localMediaDb.nextId;
      inserts.add(entry);
      if (!copy && source != null) removals.add(source.id);
    }
    for (final update in updates.entries) {
      await localMediaDb.updateEntry(update.key, update.value);
    }
    if (inserts.isNotEmpty) {
      await localMediaDb.insertEntries(inserts);
    }
    if (removals.isNotEmpty) {
      await localMediaDb.removeIds(removals);
    }
  }

  /// Deletes the staged copies of [session] and forgets the session.
  Future<bool> discard(RefraEditSession session) async {
    final outputs = await refreshOutputs(session);
    final entries = await localMediaDb.loadEntriesByUris(outputs.map((o) => o.uri).toSet());
    if (entries.isNotEmpty) {
      var success = true;
      await for (final event in mediaEditService.delete(
        opId: mediaEditService.newOpId,
        entries: entries,
      )) {
        if (!event.success) success = false;
      }
      if (!success) return false;
      await localMediaDb.removeIds(entries.map((entry) => entry.id).toSet());
    }
    final store = await _store();
    await store.deleteSession(session.id);
    unawaited(reloadPagedSummaries());
    return true;
  }

  /// Removes sessions whose staged files are already gone.
  ///
  /// Run when the session list opens, so a copy the user deleted from another app does not stay
  /// listed as a session that can no longer be opened or moved back.
  Future<void> pruneMissingSessions() async {
    final store = await _store();
    final sessions = await store.getSessions();
    for (final session in sessions.where((s) => s.status == RefraEditSessionStatus.active)) {
      // Cataloguing first keeps a live copy from being mistaken for a missing one.
      final outputs = await refreshOutputs(session);
      if (outputs.isEmpty) {
        await store.deleteSession(session.id);
        continue;
      }
      final entries = await localMediaDb.loadEntriesByUris(outputs.map((o) => o.uri).toSet());
      if (entries.isEmpty) {
        await store.deleteSession(session.id);
      }
    }
  }

  // -- first-run explainer ----------------------------------------------------

  static const String _introSeenKey = 'refraEditIntroSeen';

  Future<bool> hasSeenIntro() async {
    final meta = AppMetaStore(await _provider.open());
    final values = await meta.read({_introSeenKey});
    return values[_introSeenKey] == 'true';
  }

  Future<void> markIntroSeen() async {
    final meta = AppMetaStore(await _provider.open());
    await meta.write({_introSeenKey: 'true'});
  }
}

typedef _StagedFile = ({String uri, String name, int sizeBytes});

const refraEditService = RefraEditService();
