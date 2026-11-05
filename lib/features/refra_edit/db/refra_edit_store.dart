import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:drift/drift.dart';

/// Owns the two copy-first edit tables.
///
/// A session is one edited copy; its outputs are every file it produced. Keeping them as rows
/// (rather than only scanning the folder) lets the app answer "how many results did this edit
/// produce" and "where did this copy come from" without guessing.
class RefraEditStore {
  final AppDatabase db;

  new(this.db);

  Stream<List<RefraEditSession>> watchSessions() {
    final query = db.select(db.refraEditSessionRows)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(RefraEditSession.fromRow).toList(growable: false));
  }

  Future<List<RefraEditSession>> getSessions() async {
    final query = db.select(db.refraEditSessionRows)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return (await query.get()).map(RefraEditSession.fromRow).toList(growable: false);
  }

  Future<RefraEditSession?> getSession(String id) async {
    final row = await (db.select(db.refraEditSessionRows)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : RefraEditSession.fromRow(row);
  }

  Future<void> insertSession(RefraEditSession session) async {
    await db.into(db.refraEditSessionRows).insert(
      RefraEditSessionRowsCompanion.insert(
        id: session.id,
        sourceEntryId: Value(session.sourceEntryId),
        sourceUri: session.sourceUri,
        sourcePath: Value(session.sourcePath),
        sourceDirectory: Value(session.sourceDirectory),
        sourceName: session.sourceName,
        sourceMimeType: session.sourceMimeType,
        stagingDirectory: session.stagingDirectory,
        stagedUri: session.stagedUri,
        createdAt: session.createdAt.millisecondsSinceEpoch,
        status: Value(session.status.name),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> addOutput(RefraEditOutput output) async {
    await db.into(db.refraEditOutputRows).insert(
      RefraEditOutputRowsCompanion.insert(
        id: output.id,
        sessionId: output.sessionId,
        uri: output.uri,
        path: Value(output.path),
        fileName: output.fileName,
        kind: output.kind.name,
        sizeBytes: Value(output.sizeBytes),
        createdAt: output.createdAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<List<RefraEditOutput>> getOutputs(String sessionId) async {
    final query = db.select(db.refraEditOutputRows)
      ..where((t) => t.sessionId.equals(sessionId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return (await query.get()).map(RefraEditOutput.fromRow).toList(growable: false);
  }

  /// Every recorded output, newest first, for the records page.
  Future<List<RefraEditOutput>> getAllOutputs() async {
    final query = db.select(db.refraEditOutputRows)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return (await query.get()).map(RefraEditOutput.fromRow).toList(growable: false);
  }

  /// Rewrites where an output lives, after a move or copy changed its uri and path.
  Future<void> updateOutputLocation(
    String id, {
    required String uri,
    required String path,
    required String fileName,
    required int sizeBytes,
  }) async {
    await (db.update(db.refraEditOutputRows)..where((t) => t.id.equals(id))).write(
      RefraEditOutputRowsCompanion(
        uri: Value(uri),
        path: Value(path),
        fileName: Value(fileName),
        sizeBytes: Value(sizeBytes),
      ),
    );
  }

  Future<void> deleteOutputs(Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    await (db.delete(db.refraEditOutputRows)..where((t) => t.id.isIn(list))).go();
  }

  /// Forgets sessions that no longer own a single output row.
  Future<void> deleteSessionsWithoutOutputs() async {
    final sessions = await getSessions();
    final alive = (await getAllOutputs()).map((o) => o.sessionId).toSet();
    final orphans = sessions.where((session) => !alive.contains(session.id)).map((session) => session.id).toList(growable: false);
    if (orphans.isEmpty) return;
    await (db.delete(db.refraEditSessionRows)..where((t) => t.id.isIn(orphans))).go();
  }

  /// Deletes every session and output row, leaving the files untouched.
  ///
  /// The records page deletes the files itself (one entry per file), so clearing the
  /// bookkeeping must not go through the per-session path.
  Future<void> clearAll() async {
    await db.delete(db.refraEditOutputRows).go();
    await db.delete(db.refraEditSessionRows).go();
  }

  /// Output counts per session, for the session list's "results" column.
  Stream<Map<String, int>> watchOutputCounts() {
    final count = db.refraEditOutputRows.id.count();
    final query = db.selectOnly(db.refraEditOutputRows)
      ..addColumns([db.refraEditOutputRows.sessionId, count])
      ..groupBy([db.refraEditOutputRows.sessionId]);
    return query.watch().map(
      (rows) => {
        for (final row in rows) row.read(db.refraEditOutputRows.sessionId)!: row.read(count) ?? 0,
      },
    );
  }

  Future<void> setSessionStatus(String id, RefraEditSessionStatus status) async {
    await (db.update(db.refraEditSessionRows)..where((t) => t.id.equals(id))).write(
      RefraEditSessionRowsCompanion(status: Value(status.name)),
    );
  }

  Future<void> deleteSession(String id) async {
    await (db.delete(db.refraEditOutputRows)..where((t) => t.sessionId.equals(id))).go();
    await (db.delete(db.refraEditSessionRows)..where((t) => t.id.equals(id))).go();
  }

  /// Sessions still holding a staged copy, used by the storage summary and cleanup.
  Future<List<RefraEditSession>> getActiveSessions() async {
    final query = db.select(db.refraEditSessionRows)
      ..where((t) => t.status.equals(RefraEditSessionStatus.active.name));
    return (await query.get()).map(RefraEditSession.fromRow).toList(growable: false);
  }
}
