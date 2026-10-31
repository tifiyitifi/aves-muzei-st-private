import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v7 -> v8 adds group descriptions and applied-rule targets, and drops
/// the session table. Ranges, rules, presets and groups must survive untouched.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v7 database gains descriptions and usage targets and loses sessions', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          // A real database has had this table since v1; only the tables the
          // migration touches are recreated here.
          raw.execute('CREATE TABLE appMeta (key TEXT NOT NULL PRIMARY KEY, value TEXT)');
          raw.execute(
            'CREATE TABLE wallpaper_groups ('
            'id TEXT NOT NULL PRIMARY KEY, '
            "name TEXT NOT NULL DEFAULT '', "
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'current INTEGER NOT NULL DEFAULT 0, '
            'position INTEGER NOT NULL DEFAULT 0, '
            'createdAt INTEGER NOT NULL, '
            'updatedAt INTEGER NOT NULL)',
          );
          raw.execute("INSERT INTO wallpaper_groups (id, name, position, createdAt, updatedAt) VALUES ('g1', 'Trips', 0, 1, 2)");
          raw.execute(
            'CREATE TABLE visible_ranges ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'scope TEXT NOT NULL, '
            'ownerId TEXT NOT NULL, '
            "baseName TEXT NOT NULL DEFAULT '', "
            "basePresetId TEXT NOT NULL DEFAULT '', "
            "baseFilters TEXT NOT NULL DEFAULT '[]', "
            "orderMode TEXT NOT NULL DEFAULT 'intersectFirst', "
            'locked INTEGER NOT NULL DEFAULT 0, '
            'permissions TEXT, '
            'createdAt INTEGER NOT NULL, '
            'updatedAt INTEGER NOT NULL)',
          );
          raw.execute("INSERT INTO visible_ranges (id, scope, ownerId, createdAt, updatedAt) VALUES ('gallery', 'gallery', 'gallery', 1, 2)");
          raw.execute(
            'CREATE TABLE visible_range_rules ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'rangeId TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'position INTEGER NOT NULL DEFAULT 0, '
            "label TEXT NOT NULL DEFAULT '', "
            "description TEXT NOT NULL DEFAULT '', "
            "filters TEXT NOT NULL DEFAULT '[]', "
            'active INTEGER NOT NULL DEFAULT 1)',
          );
          raw.execute("INSERT INTO visible_range_rules (id, rangeId, kind, label, description) VALUES ('r1', 'gallery', 'restriction', 'Mine', 'keep me')");
          raw.execute(
            'CREATE TABLE visible_range_sessions ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'rangeId TEXT NOT NULL, '
            'ruleId TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'mode TEXT NOT NULL, '
            "initialFilters TEXT NOT NULL DEFAULT '[]', "
            "finalFilters TEXT NOT NULL DEFAULT '[]', "
            'createdAt INTEGER NOT NULL)',
          );
          raw.execute("INSERT INTO visible_range_sessions (id, rangeId, ruleId, kind, mode, createdAt) VALUES ('s1', 'gallery', 'r1', 'restriction', 'override', 1)");
          raw.execute('CREATE INDEX idx_visible_range_sessions_rangeId ON visible_range_sessions(rangeId)');
          raw.execute('PRAGMA user_version = 7');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final columns = (await db.customSelect('PRAGMA table_info(wallpaper_groups)').get()).map((row) => row.data['name']).toSet();
    expect(columns, contains('description'));

    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((row) => row.data['name']).toSet();
    expect(tables, contains('visible_range_rule_usage'));
    expect(tables, isNot(contains('visible_range_sessions')));

    // Existing data survives, and the new column reads as empty.
    final groups = await WallpaperGroupStore(db).loadGroups();
    expect(groups.single.name, 'Trips');
    expect(groups.single.description, isEmpty);
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(range!.rules.single.label, 'Mine');
    expect(range.rules.single.description, 'keep me');
    expect(await db.select(db.visibleRangeRuleUsageRows).get(), isEmpty);

    final indexes = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get()).map((row) => row.data['name']).toSet();
    expect(indexes, contains('idx_visible_range_rule_usage_rangeId'));
  });

  test('a fresh database has the v8 shape', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final columns = (await db.customSelect('PRAGMA table_info(wallpaper_groups)').get()).map((row) => row.data['name']).toSet();
    expect(columns, contains('description'));
    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((row) => row.data['name']).toSet();
    expect(tables, contains('visible_range_rule_usage'));
    expect(tables, isNot(contains('visible_range_sessions')));
  });
}
