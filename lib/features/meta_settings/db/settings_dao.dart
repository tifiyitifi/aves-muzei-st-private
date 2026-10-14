import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:drift/drift.dart';

const _log = AreaKeyLog(LogKeys.settings);

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
      final type = _readableType(row.key, row.type);
      if (type != null) {
        result[row.key] = (type: type, raw: row.value);
      }
    }
    return result;
  }

  /// One persisted value by key, or null when absent or unreadable.
  Future<MetaSettingRow?> load(String key) async {
    final row = await (db.select(db.settingsValuesTable)..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    final type = _readableType(row.key, row.type);
    if (type == null) return null;
    return (type: type, raw: row.value);
  }

  /// Decodes a persisted type tag, warning and returning null for one that
  /// cannot be read: an unknown tag (corruption or a future rename) or
  /// `enumeration`, which the storage path never writes.
  static SettingValueType? _readableType(String key, String raw) {
    final type = SettingValueType.tryParse(raw);
    if (type == null || type == SettingValueType.enumeration) {
      _log.w('unreadable setting type=$raw for key=$key, falling back to the default');
      return null;
    }
    return type;
  }

  Future<void> upsert(String key, SettingValueType type, String raw) async {
    await db.into(db.settingsValuesTable).insertOnConflictUpdate(
          SettingsValuesTableCompanion.insert(
            key: key,
            type: type.storageType.name,
            value: raw,
            // the companion's `DO UPDATE SET` only covers present columns, so the
            // timestamp must be written explicitly to advance on conflict
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> remove(String key) async {
    await (db.delete(db.settingsValuesTable)..where((t) => t.key.equals(key))).go();
  }

  Future<void> clear() async {
    await db.delete(db.settingsValuesTable).go();
  }
}
