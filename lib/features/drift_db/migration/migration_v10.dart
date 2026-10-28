import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v9 -> v10: a wallpaper group gains per-group home/lock effects.
///
/// The default `{}` is the identity configuration (no blur, dim or grey), so an
/// upgraded group keeps showing its photos untouched until the user edits its
/// effects page.
///
/// A database that upgrades through v7 creates the table with the current shape,
/// so the column may already be there; the same goes for fixtures that never
/// created it. Both cases are skipped instead of failing the upgrade.
class MigrationV10 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final columns = await db.customSelect('PRAGMA table_info(wallpaper_groups)').get();
    if (columns.isEmpty) return;
    if (columns.any((row) => row.data['name'] == 'effects')) return;
    await m.addColumn(db.wallpaperGroupRows, db.wallpaperGroupRows.effects);
  }
}
