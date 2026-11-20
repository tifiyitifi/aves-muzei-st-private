import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Owns the `batch_results` table.
///
/// The store only knows rows: which file a row points at, which source it came
/// from, and whether it is still waiting for a decision. File operations belong
/// to `BatchResultsService`, so a row can be inspected without touching storage.
class BatchResultStore {
  final AppDatabase db;

  new(this.db);

  Future<List<BatchResult>> getResults() async {
    final query = db.select(db.batchResultRows)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return _mapRows(await query.get());
  }

  Future<List<BatchResult>> getPending() async {
    final query = db.select(db.batchResultRows)
      ..where((t) => t.status.equals(BatchResultStatus.pending.name))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return _mapRows(await query.get());
  }

  /// Older pending results of [sourceUri], newest first, excluding [exceptId].
  ///
  /// Used by the replace-previous mode to decide what the new result supersedes.
  Future<List<BatchResult>> getPendingBySource(String sourceUri, {String? exceptId}) async {
    final query = db.select(db.batchResultRows)
      ..where((t) {
        final base = t.sourceUri.equals(sourceUri) & t.status.equals(BatchResultStatus.pending.name);
        return exceptId == null ? base : base & t.id.equals(exceptId).not();
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return _mapRows(await query.get());
  }

  Future<void> insertResult(BatchResult result) async {
    await db.into(db.batchResultRows).insert(
      BatchResultRowsCompanion.insert(
        id: result.id,
        jobId: result.jobId,
        sourceEntryId: Value(result.sourceEntryId),
        sourceUri: result.sourceUri,
        sourcePath: Value(result.sourcePath),
        sourceDirectory: Value(result.sourceDirectory),
        sourceName: result.sourceName,
        resultUri: result.resultUri,
        resultPath: Value(result.resultPath),
        resultFileName: result.resultFileName,
        resultMimeType: Value(result.resultMimeType),
        resultSizeBytes: Value(result.resultSizeBytes),
        actionsJson: Value(result.actionsJson),
        createdAt: result.createdAt.millisecondsSinceEpoch,
        status: Value(result.status.name),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Rewrites where a result lives after a rename or move changed its uri.
  Future<void> updateResultLocation(
    String id, {
    required String uri,
    required String path,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    await (db.update(db.batchResultRows)..where((t) => t.id.equals(id))).write(
      BatchResultRowsCompanion(
        resultUri: Value(uri),
        resultPath: Value(path),
        resultFileName: Value(fileName),
        resultMimeType: Value(mimeType),
        resultSizeBytes: Value(sizeBytes),
      ),
    );
  }

  Future<void> deleteResults(Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    await (db.delete(db.batchResultRows)..where((t) => t.id.isIn(list))).go();
  }

  List<BatchResult> _mapRows(List<BatchResultRow> rows) => rows.map(BatchResult.fromRow).toList(growable: false);
}
