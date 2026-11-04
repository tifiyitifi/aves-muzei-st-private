import 'dart:async';

import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/refra_edit/db/refra_edit_store.dart';
import 'package:aves/features/refra_edit/log.dart';
import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/enums.dart';


/// Copy-first editing.
///
/// Every session copies the source into `Pictures/aves_refra_edit/<sessionId>` and only ever
/// edits that copy: the built-in editor and third-party editors both receive the staged uri, so an
/// OEM editor that overwrites its input cannot destroy the user's original. The session row
/// remembers the source directory, which is the only destination the copies can be moved back to.
class RefraEditService {
  static const _editChannel = AvesMethodChannel('deckers.thibault/aves/media_edit');

  final AppDatabaseProvider? provider;

  const new({this.provider});

  AppDatabaseProvider get _provider => provider ?? getIt<AppDatabaseProvider>();

  Future<RefraEditStore> _store() async => RefraEditStore(await _provider.open());

  /// Folder every editor of a session writes to, relative to the Pictures root.
  static String outputRelativePath(String sessionId) => 'Pictures/aves_refra_edit/$sessionId';

  static String newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<RefraEditStore> store() => _store();

  /// Absolute staging directory for [sessionId].
  Future<String> stagingDirectory(String sessionId) async {
    final result = await _editChannel.invokeMethod('refraStagingDir', <String, Object?>{
      'sessionId': sessionId,
    });
    if (result is! String || result.isEmpty) {
      throw StateError('Cannot resolve the staging directory for session $sessionId');
    }
    return result;
  }

  /// Copies [source] into a fresh staging directory and records the session.
  Future<RefraEditSession> createSession(AvesEntry source) async {
    final sessionId = newSessionId();
    final stagingDir = await stagingDirectory(sessionId);

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
    return session;
  }

  /// Opens the built-in editor on the session's staged copy.
  ///
  /// Returns true when the editor reported a save; false on cancel or failure.
  Future<bool> openBuiltIn(RefraEditSession session) async {
    final result = await appService.refraEdit(session.stagedUri, outputRelativePath(session.id));
    final error = result['error'] as String?;
    if (error != null) {
      refraEditLog.w('built-in editor failed: $error');
      return false;
    }
    await refreshOutputs(session);
    return true;
  }

  /// Opens the system editor chooser on the session's staged copy.
  ///
  /// Returns true when a third-party editor reported a result; outputs are recorded by rescanning
  /// the session folder, because an external app gives the app no reliable list of written files.
  Future<bool> openExternal(RefraEditSession session) async {
    final fields = await appService.edit(session.stagedUri, session.sourceMimeType);
    if (fields['error'] != null) return false;
    await refreshOutputs(session);
    return true;
  }

  /// Reconciles the recorded outputs with the files currently in the staging directory.
  Future<List<RefraEditOutput>> refreshOutputs(RefraEditSession session) async {
    final result = await _editChannel.invokeMethod('refraListOutputs', <String, Object?>{
      'relativePath': outputRelativePath(session.id),
      'directory': session.stagingDirectory,
    });
    final store = await _store();
    final known = await store.getOutputs(session.id);
    final knownUris = known.map((o) => o.uri).toSet();
    if (result is List) {
      for (final raw in result) {
        if (raw is! Map) continue;
        final uri = raw['uri'] as String?;
        if (uri == null || knownUris.contains(uri)) continue;
        final size = (raw['size'] as num?)?.toInt() ?? 0;
        final name = (raw['name'] as String?) ?? Uri.parse(uri).pathSegments.last;
        await store.addOutput(
          RefraEditOutput(
            id: '${session.id}-${DateTime.now().microsecondsSinceEpoch}',
            sessionId: session.id,
            uri: uri,
            path: '',
            fileName: name,
            kind: session.stagedUri == uri ? RefraEditOutputKind.staged : RefraEditOutputKind.unknown,
            sizeBytes: size,
            createdAt: DateTime.now(),
          ),
        );
      }
    }
    return store.getOutputs(session.id);
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
    return true;
  }

  /// Removes sessions whose staged files are already gone from the database.
  Future<void> pruneMissingSessions() async {
    final store = await _store();
    final sessions = await store.getSessions();
    for (final session in sessions.where((s) => s.status == RefraEditSessionStatus.active)) {
      final outputs = await store.getOutputs(session.id);
      if (outputs.isEmpty) continue;
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

const refraEditService = RefraEditService();
