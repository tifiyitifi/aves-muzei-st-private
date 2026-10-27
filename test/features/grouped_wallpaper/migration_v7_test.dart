import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v6 -> v7 adds the wallpaper group table and nothing else: existing
/// visible ranges (including wallpaper-scope ones) must survive untouched.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v6 database gains the group table and keeps its ranges', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
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
          raw.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);
    expect(version, 8);

    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'wallpaper_groups'").get();
    expect(tables.map((row) => row.data['name']), ['wallpaper_groups']);

    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_wallpaper_groups_position'").get();
    expect(indexes, hasLength(1));

    // The v5 rows are still there and readable through the current definitions.
    final ranges = await db.select(db.visibleRangeRows).get();
    expect(ranges.single.id, 'gallery');
    expect(ranges.single.scope, 'gallery');
  });

  test('a fresh database has the group table and its index', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final store = WallpaperGroupStore(db);
    await store.saveGroups([
      const WallpaperGroup(id: 'a', createdAt: 1, updatedAt: 1),
      const WallpaperGroup(id: 'b', createdAt: 1, updatedAt: 1),
    ]);

    final groups = await store.loadGroups();
    expect(groups.map((group) => group.number), [1, 2]);
    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_wallpaper_groups_position'").get();
    expect(indexes, hasLength(1));
  });
}
