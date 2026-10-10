import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Owns the `appMeta` table: fork-only key/value bookkeeping.
///
/// Deliberately generic: the one-time legacy import keeps its state here (see
/// `migration/legacy_import_state_store.dart`), so this store only knows how to
/// read and write string values and never interprets them.
class AppMetaStore {
  final AppDatabase db;

  new(this.db);

  /// Reads the requested [keys] in one query; missing keys are simply absent.
  Future<Map<String, String>> read(Set<String> keys) async {
    if (keys.isEmpty) return const {};
    final rows = await (db.select(db.appMetaTable)..where((t) => t.key.isIn(keys.toList()))).get();
    return {
      for (final row in rows)
        if (row.value != null) row.key: row.value!,
    };
  }

  /// Upserts every entry of [values].
  Future<void> write(Map<String, String> values) async {
    for (final entry in values.entries) {
      await db.into(db.appMetaTable).insertOnConflictUpdate(
            AppMetaTableCompanion.insert(key: entry.key, value: Value(entry.value)),
          );
    }
  }
}
