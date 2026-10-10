import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Builds an [Insertable] from a raw `column name -> value` map.
///
/// Keys are the SQL column names (camelCase, pinned via `.named(...)` in the
/// table definitions), so callers reuse the existing `toDbMap()` /
/// `toDatabaseMap()` serializers on the domain models. Prefer
/// [batchInsertReplace] / [insertReplace], which infer the generated row type.
RawValuesInsertable<D> rawInsertable<D>(Map<String, Object?> map) {
  return RawValuesInsertable<D>(_columns(map));
}

Map<String, Expression> _columns(Map<String, Object?> map) => <String, Expression>{
  for (final entry in map.entries) entry.key: Variable<Object>(entry.value),
};

/// Queues an `INSERT OR REPLACE` of [map] into [table] inside [batch].
///
/// `D` is inferred from [table], so callers never name the generated row type.
void batchInsertReplace<T extends Table, D>(Batch batch, TableInfo<T, D> table, Map<String, Object?> map) {
  batch.insert(table, RawValuesInsertable<D>(_columns(map)), mode: InsertMode.insertOrReplace);
}

/// Inserts or replaces [map] into [table].
///
/// `D` is inferred from [table], so callers never name the generated row type.
Future<void> insertReplace<T extends Table, D>(AppDatabase db, TableInfo<T, D> table, Map<String, Object?> map) {
  return db.into(table).insert(RawValuesInsertable<D>(_columns(map)), mode: InsertMode.insertOrReplace);
}

/// Reads every row of [table] as raw column maps.
///
/// The physical table name and row shape stay inside the owning domain store;
/// callers only see domain objects produced by the mapping function.
Future<List<QueryRow>> selectAllRows(AppDatabase db, String table) {
  return db.customSelect('SELECT * FROM $table').get();
}

/// Reads the rows of [table] whose primary key `id` is in [ids], mapped through
/// [mapRow].
Future<Set<T>> selectByIds<T>(AppDatabase db, String table, Set<int> ids, T Function(Map<String, Object?>) mapRow) async {
  final result = <T>{};
  if (ids.isEmpty) return result;
  final rows = await db.customSelect('SELECT * FROM $table WHERE id IN (${ids.join(',')})').get();
  for (final row in rows) {
    result.add(mapRow(row.data));
  }
  return result;
}
