import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// Owns the `trash` table (path + deletion date per trashed entry).
class TrashStore {
  static const _table = 'trash';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.trashTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<Set<TrashDetails>> loadAll() async {
    final result = <TrashDetails>{};
    for (final row in await selectAllRows(db, _table)) {
      result.add(TrashDetails.fromMap(row.data));
    }
    return result;
  }

  Future<void> update(int id, TrashDetails? details) async {
    await db.batch((batch) {
      batch.deleteWhere(db.trashTable, (t) => t.id.equals(id));
      if (details != null) {
        batchInsertReplace(batch, db.trashTable, details.toDbMap());
      }
    });
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.trashTable, (t) => t.id.equals(id));
  }
}
