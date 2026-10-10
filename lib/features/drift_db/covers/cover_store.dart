import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

/// Owns the `covers` table (per-collection cover overrides).
class CoverStore {
  static const _table = 'covers';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.coversTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<Set<CoverRow>> loadAll() async {
    final result = <CoverRow>{};
    for (final row in await selectAllRows(db, _table)) {
      final cover = CoverRow.fromMap(row.data);
      if (cover != null) {
        result.add(cover);
      } else {
        debugPrint('$runtimeType failed to deserialize cover from row=${row.data}');
      }
    }
    return result;
  }

  Future<void> add(Set<CoverRow> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batchInsertReplace(batch, db.coversTable, row.toDbMap());
      }
    });
  }

  Future<void> updateEntryId(int id, CoverRow row) async {
    await db.batch((batch) {
      batch.deleteWhere(db.coversTable, (t) => t.entryId.equals(id));
      batch.insert(db.coversTable, rawInsertable(row.toDbMap()), mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> remove(Set<CollectionFilter> filters) async {
    if (filters.isEmpty) return;

    // for backward compatibility, remove stored JSON instead of removing de/reserialized filters
    final obsoleteFilterJson = <String>{};
    for (final row in await selectAllRows(db, _table)) {
      final filterJson = row.data['filter'] as String?;
      if (filterJson != null) {
        final filter = CollectionFilter.fromJson(filterJson);
        if (filters.any((v) => filter == v)) {
          obsoleteFilterJson.add(filterJson);
        }
      }
    }

    if (obsoleteFilterJson.isEmpty) return;
    await db.batch((batch) {
      for (final filterJson in obsoleteFilterJson) {
        batch.deleteWhere(db.coversTable, (t) => t.filter.equals(filterJson));
      }
    });
  }

  void deleteByEntryIdInBatch(Batch batch, int id) {
    batch.deleteWhere(db.coversTable, (t) => t.entryId.equals(id));
  }
}
