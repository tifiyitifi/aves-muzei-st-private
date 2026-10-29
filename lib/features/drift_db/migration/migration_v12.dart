import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v11 -> v12: the grouped wallpaper keeps a usage history.
///
/// The table is new and independent of the groups: it deliberately has no foreign
/// key, so deleting a group never rewrites what the wallpaper showed before, and
/// the page can still label a row with the group's stored name.
///
/// A database that upgrades through an earlier version creates the table with the
/// current shape, so the create is skipped when it already exists.
class MigrationV12 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'grouped_wallpaper_history'").get();
    if (tables.isEmpty) await m.createTable(db.groupedWallpaperHistoryRows);
    await createNewIndexes(db);
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
