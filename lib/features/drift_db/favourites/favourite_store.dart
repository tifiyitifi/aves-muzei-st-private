import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/favourites.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// Owns the `favourites` table (entry ids).
class FavouriteStore {
  static const _table = 'favourites';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.favouritesTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<Set<FavouriteRow>> loadAll() async {
    final result = <FavouriteRow>{};
    for (final row in await selectAllRows(db, _table)) {
      result.add(FavouriteRow.fromMap(row.data));
    }
    return result;
  }

  Future<void> add(Set<FavouriteRow> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batchInsertReplace(batch, db.favouritesTable, row.toDbMap());
      }
    });
  }

  Future<void> updateId(int id, FavouriteRow row) async {
    await db.batch((batch) {
      batch.deleteWhere(db.favouritesTable, (t) => t.id.equals(id));
      batch.insert(db.favouritesTable, rawInsertable(row.toDbMap()), mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> remove(Set<FavouriteRow> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batch.deleteWhere(db.favouritesTable, (t) => t.id.equals(row.entryId));
      }
    });
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.favouritesTable, (t) => t.id.equals(id));
  }
}
