import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Owns the `appMeta` table: fork-only key/value bookkeeping.
///
/// Currently only the one-time legacy import flag lives here.
class AppMetaStore {
  static const _legacyImportedKey = 'legacyImported';

  final AppDatabase db;

  new(this.db);

  Future<bool> isLegacyImported() async {
    final rows = await (db.select(db.appMetaTable)..where((t) => t.key.equals(_legacyImportedKey))).get();
    return rows.isNotEmpty && rows.first.value == 'true';
  }

  Future<void> markLegacyImported() async {
    await db.into(db.appMetaTable).insertOnConflictUpdate(
          AppMetaTableCompanion.insert(key: _legacyImportedKey, value: const Value('true')),
        );
  }
}
