import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/meta_settings/model/enum/setting_value_type.dart';

/// One persisted metadata-setting value, decoded from its row.
typedef MetaSettingRow = ({SettingValueType type, String raw});

/// Owns the `settingsValues` table.
///
/// Thin raw-SQL seam: callers (the metadata store, the seeder) speak in terms
/// of `key`/`type`/encoded `raw` strings and never touch Drift companions.
class MetaSettingsDao {
  final AppDatabase db;

  new(this.db);

  Future<Map<String, MetaSettingRow>> loadAll() async {
    final rows = await db.select(db.settingsValuesTable).get();
    final result = <String, MetaSettingRow>{};
    for (final row in rows) {
      final type = SettingValueType.tryParse(row.type);
      if (type != null) {
        result[row.key] = (type: type, raw: row.value);
      }
    }
    return result;
  }

  Future<void> upsert(String key, SettingValueType type, String raw) async {
    await db.into(db.settingsValuesTable).insertOnConflictUpdate(
          SettingsValuesTableCompanion.insert(key: key, type: type.storageType.name, value: raw),
        );
  }

  Future<void> remove(String key) async {
    await (db.delete(db.settingsValuesTable)..where((t) => t.key.equals(key))).go();
  }

  Future<void> clear() async {
    await db.delete(db.settingsValuesTable).go();
  }
}
