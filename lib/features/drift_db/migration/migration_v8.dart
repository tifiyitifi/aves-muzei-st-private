import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v7 -> v8: group descriptions and applied-rule targets, no sessions.
///
/// The session table only held "activate to media set" history so a delta could
/// be written back to its rule. The feature now remembers which targets were
/// used instead (one row per target, never reused), so the table is dropped: the
/// user's ranges, rules, presets and groups are untouched.
class MigrationV8 {
  final AppDatabase db;

  new(this.db);

  static const List<String> _indexes = [
    'CREATE INDEX IF NOT EXISTS idx_visible_range_rule_usage_rangeId ON visible_range_rule_usage(rangeId)',
  ];

  /// Creates the v8 indexes on a fresh database (called from `onCreate`).
  static Future<void> createNewIndexes(AppDatabase db) async {
    for (final statement in _indexes) {
      await db.customStatement(statement);
    }
  }

  Future<void> run(Migrator m) async {
    // A database upgraded from v6 already created `wallpaper_groups` through
    // `MigrationV7`, which builds the table from the *current* definition and
    // therefore already carries `description`. Only a v7 database needs the
    // column added.
    final columns = await db.customSelect('PRAGMA table_info(wallpaper_groups)').get();
    final hasDescription = columns.any((row) => row.data['name'] == 'description');
    if (!hasDescription) {
      await m.addColumn(db.wallpaperGroupRows, db.wallpaperGroupRows.description);
    }
    await m.createTable(db.visibleRangeRuleUsageRows);
    // Only a database that was at v5..v7 still has the session table; a v4
    // install never created it, hence the `IF EXISTS` form.
    await m.deleteTable('visible_range_sessions');
    await createNewIndexes(db);
  }
}
