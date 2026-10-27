import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v8 -> v9: a visible range's base gains an activation flag.
///
/// Existing ranges were always governed by their base, so the column defaults to
/// `true` and an upgrade changes no behaviour. The flag exists for wallpaper
/// groups, whose base is switched off (but kept) when the group is cleared.
///
/// A database that upgrades through v5 creates the table with the current shape,
/// so the column may already be there; the same goes for fixtures that never
/// created it. Both cases are skipped instead of failing the upgrade.
class MigrationV9 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final columns = await db.customSelect('PRAGMA table_info(visible_ranges)').get();
    if (columns.isEmpty) return;
    if (columns.any((row) => row.data['name'] == 'baseActive')) return;
    await m.addColumn(db.visibleRangeRows, db.visibleRangeRows.baseActive);
  }
}
