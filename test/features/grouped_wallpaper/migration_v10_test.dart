import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v9 -> v10 adds per-group effects without changing how existing groups
/// look: the identity configuration keeps every photo sharp.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v9 database gains identity effects on every group', () async {
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
            "description TEXT NOT NULL DEFAULT '', "
            'enabled INTEGER NOT NULL DEFAULT 1, '
            'current INTEGER NOT NULL DEFAULT 0, '
            'position INTEGER NOT NULL DEFAULT 0, '
            'createdAt INTEGER NOT NULL, '
            'updatedAt INTEGER NOT NULL)',
          );
          raw.execute(
            'INSERT INTO wallpaper_groups (id, name, enabled, current, position, createdAt, updatedAt) '
            "VALUES ('wallpaper.group.all', '@wallpaperGroupDefaultAll', 1, 1, 0, 1, 2)",
          );
          raw.execute('PRAGMA user_version = 9');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final groups = await WallpaperGroupStore(db).loadGroups();
    expect(groups, hasLength(1));
    expect(groups.single.id, 'wallpaper.group.all');
    expect(groups.single.effects, const WallpaperEffectsConfig());
    expect(groups.single.effects.home.isIdentity, isTrue);
  });

  test('a fresh database stores and reads per-group effects', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final columns = (await db.customSelect('PRAGMA table_info(wallpaper_groups)').get()).map((row) => row.data['name']).toSet();
    expect(columns, contains('effects'));

    const group = WallpaperGroup(
      id: 'group.1',
      name: 'Private',
      enabled: true,
      current: true,
      createdAt: 1,
      updatedAt: 2,
      effects: WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 250, dim: 128),
        lock: WallpaperEffects(blur: 400, grey: 300),
        link: false,
      ),
    );
    await WallpaperGroupStore(db).saveGroups([group]);

    final stored = (await WallpaperGroupStore(db).loadGroups()).single;
    expect(stored.effects, group.effects);
    expect(stored.effects.effectiveLock, group.effects.lock);
  });
}
