import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v6 -> v7: adds the wallpaper-group table.
///
/// Only the group list is new. Each group's visible range already lives in the
/// v5 `visible_ranges` tables under `scope = wallpaper`, so this migration adds
/// one table and one index and leaves every existing row untouched.
class MigrationV7 {
  final AppDatabase db;

  new(this.db);

  static const List<String> _indexes = [
    'CREATE INDEX IF NOT EXISTS idx_wallpaper_groups_position ON wallpaper_groups(position)',
  ];

  /// Creates the v7 indexes on a fresh database (called from `onCreate`).
  static Future<void> createNewIndexes(AppDatabase db) async {
    for (final statement in _indexes) {
      await db.customStatement(statement);
    }
  }

  Future<void> run(Migrator m) async {
    await m.createTable(db.wallpaperGroupRows);
    await createNewIndexes(db);
  }
}
