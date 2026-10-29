import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v10 -> v11: a wallpaper group owns its auto-advance contract.
///
/// The interval defaults to `0` (off) and the ordering to `newThenRandom`, both
/// matching Muzei. The ordering used to be one global `appMeta` value, so the
/// upgrade copies it into every group and then drops the key: an existing install
/// keeps the ordering it chose instead of silently returning to the default.
///
/// A database that upgrades through v7 creates the table with the current shape,
/// so the columns may already be there; the same goes for fixtures that never
/// created it. Both cases are skipped instead of failing the upgrade.
class MigrationV11 {
  /// The orderings v10 could have stored; anything else is left to the tolerant
  /// parser rather than written back as a group value.
  static const _orderings = {'inOrder', 'newThenRandom', 'random'};

  static const _globalOrderingKey = 'wallpaper.groupedOrdering';

  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final columns = await db.customSelect('PRAGMA table_info(wallpaper_groups)').get();
    if (columns.isEmpty) return;
    final names = {for (final row in columns) row.data['name']};
    if (!names.contains('interval')) await m.addColumn(db.wallpaperGroupRows, db.wallpaperGroupRows.interval);
    if (!names.contains('ordering')) await m.addColumn(db.wallpaperGroupRows, db.wallpaperGroupRows.ordering);
    await _adoptGlobalOrdering();
  }

  /// Copies the pre-v11 global ordering into every group, once.
  Future<void> _adoptGlobalOrdering() async {
    // Fixtures and very old databases may not have created the bookkeeping table
    // yet; there is nothing to migrate in that case.
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'appMeta'").get();
    if (tables.isEmpty) return;
    final rows = await db.customSelect('SELECT value FROM appMeta WHERE key = ?', variables: [const Variable<String>(_globalOrderingKey)]).get();
    final value = rows.isEmpty ? null : rows.first.data['value'];
    if (value is! String || !_orderings.contains(value)) return;
    await db.customUpdate('UPDATE wallpaper_groups SET ordering = ?', variables: [Variable<String>(value)]);
    await db.customUpdate('DELETE FROM appMeta WHERE key = ?', variables: [const Variable<String>(_globalOrderingKey)]);
  }
}
