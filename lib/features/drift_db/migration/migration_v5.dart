import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v4 -> v5: adds the visible-range tables.
///
/// The gallery keeps one range row; wallpaper groups (a later phase) add one
/// row per group under the same schema, so both scopes share the rule/session
/// machinery without a second migration.
class MigrationV5 {
  final AppDatabase db;

  new(this.db);

  static const List<String> _indexes = [
    'CREATE INDEX IF NOT EXISTS idx_visible_range_rules_rangeId ON visible_range_rules(rangeId)',
    'CREATE INDEX IF NOT EXISTS idx_visible_ranges_scope_owner ON visible_ranges(scope, ownerId)',
  ];

  /// Creates the v5 indexes on a fresh database (called from `onCreate`).
  static Future<void> createNewIndexes(AppDatabase db) async {
    for (final statement in _indexes) {
      await db.customStatement(statement);
    }
  }

  Future<void> run(Migrator m) async {
    await m.createTable(db.visibleRangePresetRows);
    await m.createTable(db.visibleRangeRows);
    await m.createTable(db.visibleRangeRuleRows);
    // `visible_range_sessions` is not created: v8 dropped it again, and a v4
    // install never had it. Only a v5..v7 database still carries the table.
    await m.createTable(db.visibleRangeKeyValues);
    await createNewIndexes(db);
  }
}
