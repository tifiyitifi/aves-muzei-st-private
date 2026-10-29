import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v10 -> v11 gives every group its own auto-advance contract, and an
/// install that had chosen a global ordering keeps it.
void main() {
  setUpAll(ensureSqlite3Loaded);

  /// A v10 `wallpaper_groups` table: no `interval` and no `ordering` column.
  Future<AppDatabase> openV10({String? globalOrdering}) async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE wallpaper_groups ('
            'id TEXT NOT NULL PRIMARY KEY, '
            "name TEXT NOT NULL DEFAULT '', "
            "description TEXT NOT NULL DEFAULT '', "
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'current INTEGER NOT NULL DEFAULT 0, '
            'position INTEGER NOT NULL DEFAULT 0, '
            'createdAt INTEGER NOT NULL, '
            'updatedAt INTEGER NOT NULL, '
            "effects TEXT NOT NULL DEFAULT '{}')",
          );
          raw.execute('CREATE TABLE appMeta (key TEXT NOT NULL PRIMARY KEY, value TEXT NULL)');
          raw.execute(
            'INSERT INTO wallpaper_groups (id, name, enabled, current, position, createdAt, updatedAt) '
            "VALUES ('wallpaper.group.all', '@wallpaperGroupDefaultAll', 1, 1, 0, 1, 2)",
          );
          if (globalOrdering != null) {
            raw.execute("INSERT INTO appMeta (key, value) VALUES ('wallpaper.groupedOrdering', '$globalOrdering')");
          }
          raw.execute('PRAGMA user_version = 10');
        },
      ),
    );
    addTearDown(db.close);
    return db;
  }

  test('a v10 database gains the default contract and adopts the global ordering', () async {
    final db = await openV10(globalOrdering: 'random');

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final groups = await WallpaperGroupStore(db).loadGroups();
    expect(groups, hasLength(1));
    expect(groups.single.interval, WallpaperInterval.never);
    expect(groups.single.ordering, GroupedWallpaperOrdering.random);
    // The global key is consumed by the upgrade: the groups own the value now.
    expect(await AppMetaStore(db).read({'wallpaper.groupedOrdering'}), isEmpty);
  });

  test('a v10 database without a global ordering keeps the default', () async {
    final db = await openV10();

    await db.customSelect('SELECT 1').get();

    final groups = await WallpaperGroupStore(db).loadGroups();
    expect(groups.single.interval, WallpaperInterval.never);
    expect(groups.single.ordering, GroupedWallpaperOrdering.newThenRandom);
  });

  test('a fresh database stores and reads per-group auto-advance', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final columns = (await db.customSelect('PRAGMA table_info(wallpaper_groups)').get()).map((row) => row.data['name']).toSet();
    expect(columns, containsAll(['interval', 'ordering']));

    await WallpaperGroupStore(db).saveGroups([
      const WallpaperGroup(
        id: 'group.1',
        name: 'Private',
        current: true,
        createdAt: 1,
        updatedAt: 2,
        interval: WallpaperInterval.h3,
        ordering: GroupedWallpaperOrdering.inOrder,
      ),
    ]);

    final stored = (await WallpaperGroupStore(db).loadGroups()).single;
    expect(stored.interval, WallpaperInterval.h3);
    expect(stored.ordering, GroupedWallpaperOrdering.inOrder);
  });
}
