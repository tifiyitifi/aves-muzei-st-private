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
  Future<RefraEditSession> createSession(AvesEntry source) async {
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
    final before = await _folderUris(session);
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
    final before = await _folderUris(session);
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

  /// Reconciles the recorded outputs with Aves' database and returns them.
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
    return outputs;
  }

  Future<void> _recordNewOutputs(
    RefraEditSession session,
    Map<String, _StagedFile> before,
    RefraEditOutputKind kind,
  ) async {
    final after = await _folderUris(session);
    final added = after.keys.where((uri) => !before.containsKey(uri)).toList();
    if (added.isEmpty) return;
    final store = await _store();
    final knownUris = (await store.getOutputs(session.id)).map((o) => o.uri).toSet();
    for (final uri in added) {
      if (knownUris.contains(uri)) continue;
      final file = after[uri]!;
      await store.addOutput(
        RefraEditOutput(
          id: '${session.id}-${DateTime.now().microsecondsSinceEpoch}',
          sessionId: session.id,
          uri: uri,
          path: '',
          fileName: file.name,
          kind: kind,
          sizeBytes: file.sizeBytes,
          createdAt: DateTime.now(),
        ),
      );
    }
    if (await _ensureEntries(added.toSet())) {
      unawaited(reloadPagedSummaries());
    }
  }

  /// Every media file currently in the staging folder, keyed by uri.
  Future<Map<String, _StagedFile>> _folderUris(RefraEditSession session) async {
    final result = await _editChannel.invokeMethod('refraListOutputs', <String, Object?>{
      'relativePath': refraEditStagingRelativeRoot,
      'directory': session.stagingDirectory,
    });
    final files = <String, _StagedFile>{};
    if (result is List) {
      for (final raw in result) {
        if (raw is! Map) continue;
        final uri = raw['uri'] as String?;
        if (uri == null) continue;
        final name = (raw['name'] as String?) ?? Uri.parse(uri).pathSegments.last;
        files[uri] = (name: name, sizeBytes: (raw['size'] as num?)?.toInt() ?? 0);
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

  /// Moves every kept output back to the directory the source came from.
  ///
  /// The caller resolves conflicts (replace / rename) before calling this, so an overwrite is
  /// always an explicit user decision.
  Future<bool> moveBack(
    RefraEditSession session, {
    required NameConflictStrategy nameConflictStrategy,
  }) async {
    if (session.sourceDirectory.isEmpty) return false;
    final outputs = await refreshOutputs(session);
    final entries = await localMediaDb.loadEntriesByUris(outputs.map((o) => o.uri).toSet());
    if (entries.isEmpty) return false;

    final destinations = <String, Set<AvesEntry>>{
      session.sourceDirectory: entries,
    };
    var success = true;
    await for (final event in mediaEditService.move(
      opId: mediaEditService.newOpId,
      entriesByDestination: destinations,
      copy: false,
      nameConflictStrategy: nameConflictStrategy,
    )) {
      if (!event.success) success = false;
    }
    if (success) {
      final store = await _store();
      await store.setSessionStatus(session.id, RefraEditSessionStatus.moved);
      unawaited(reloadPagedSummaries());
    }
    return success;
  }

  /// Deletes the staged copies and forgets the session.
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

typedef _StagedFile = ({String name, int sizeBytes});

const refraEditService = RefraEditService();
