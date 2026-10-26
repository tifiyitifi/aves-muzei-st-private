import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v5 -> v6: adds a user-editable description to presets and rules.
///
/// Pinning the current filters to a range records when and from what it was
/// created. The note is presentation only, so both columns default to an empty
/// string and existing rows stay valid.
class MigrationV6 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    await _addColumnIfMissing(m, db.visibleRangePresetRows, db.visibleRangePresetRows.description);
    await _addColumnIfMissing(m, db.visibleRangeRuleRows, db.visibleRangeRuleRows.description);
  }

  /// An install upgrading from below v5 gets its visible-range tables from the
  /// current definitions, which already carry the column. Only add what is
  /// actually missing so the chain stays correct from any starting version.
  Future<void> _addColumnIfMissing<T extends Table, D extends Object>(Migrator m, TableInfo<T, D> table, GeneratedColumn<D> column) async {
    final info = await db.customSelect('PRAGMA table_info(${table.actualTableName})').get();
    if (info.any((row) => row.data['name'] == column.name)) return;
    await m.addColumn(table, column);
  }
}
