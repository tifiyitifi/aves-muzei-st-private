import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v12 -> v13: the grouped wallpaper can use a different lock range, and
/// the usage history remembers which surface showed a photo.
///
/// The lock surface is a decoy for the home one, so both need their own records:
/// the same photo on the home and lock screens is two entries, not one. That
/// changes the history's unique key, which SQLite cannot alter in place, hence
/// the table rebuild. Existing rows all belong to the home surface, which is what
/// every build before this one drew.
///
/// A database that upgrades through an earlier version creates both tables with
/// the current shape, so each step is skipped when it already happened.
class MigrationV13 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    await _addSeparateLockRange(m);
    await _addHistorySurface(m);
    await createNewIndexes(db);
  }

  Future<void> _addSeparateLockRange(Migrator m) async {
    final columns = await db.customSelect('PRAGMA table_info(wallpaper_groups)').get();
    if (columns.isEmpty) return;
    if (columns.any((row) => row.data['name'] == 'separateLockRange')) return;
    await m.addColumn(db.wallpaperGroupRows, db.wallpaperGroupRows.separateLockRange);
  }

  Future<void> _addHistorySurface(Migrator m) async {
    final columns = await db.customSelect('PRAGMA table_info(grouped_wallpaper_history)').get();
    if (columns.isEmpty) {
      // A fixture or a database that skipped v12: the current shape is the only
      // shape such an install ever needs.
      await m.createTable(db.groupedWallpaperHistoryRows);
      return;
    }
    if (columns.any((row) => row.data['name'] == 'surface')) return;

    // Rebuild instead of `ALTER TABLE ADD COLUMN` because the unique key changes
    // with the column, and SQLite can only express that by recreating the table.
    // The rename carries the old index along, so the old table is dropped before
    // the index is created again under the same name.
    await db.customStatement('ALTER TABLE grouped_wallpaper_history RENAME TO grouped_wallpaper_history_v12');
    await m.createTable(db.groupedWallpaperHistoryRows);
    await db.customStatement(
      'INSERT INTO grouped_wallpaper_history (id, entryId, groupId, groupName, groupNumber, surface, usedAt) '
      "SELECT id, entryId, groupId, groupName, groupNumber, 'home', usedAt FROM grouped_wallpaper_history_v12",
    );
    await db.customStatement('DROP TABLE grouped_wallpaper_history_v12');
  }

  static Future<void> createNewIndexes(AppDatabase db) async {
    // The page always reads the newest rows first, and the prune keeps the same
    // order, so both walk this index.
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_grouped_wallpaper_history_used_at '
      'ON grouped_wallpaper_history (usedAt)',
    );
  }
}
