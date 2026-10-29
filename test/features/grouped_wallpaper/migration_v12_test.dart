import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/db/grouped_wallpaper_history_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v11 -> v12 adds the grouped wallpaper's usage history without touching
/// the groups it describes.
void main() {
  setUpAll(ensureSqlite3Loaded);

  /// A v11 database: the history table does not exist yet, the group table does.
  Future<AppDatabase> openV11() async {
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
            "effects TEXT NOT NULL DEFAULT '{}', "
            'interval INTEGER NOT NULL DEFAULT 0, '
            "ordering TEXT NOT NULL DEFAULT 'newThenRandom')",
          );
          raw.execute(
            'INSERT INTO wallpaper_groups (id, name, enabled, current, position, createdAt, updatedAt) '
            "VALUES ('wallpaper.group.all', '@wallpaperGroupDefaultAll', 1, 1, 0, 1, 2)",
          );
          raw.execute('PRAGMA user_version = 11');
        },
      ),
    );
    addTearDown(db.close);
    return db;
  }

  Future<Set<String>> columnsOf(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.data['name'] as String};
  }

  test('a v11 database gains the history table and its index', () async {
    final db = await openV11();

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    expect(
      await columnsOf(db, 'grouped_wallpaper_history'),
      {'id', 'entryId', 'groupId', 'groupName', 'groupNumber', 'usedAt'},
    );
    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_grouped_wallpaper_history_used_at'").get();
    expect(indexes, hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 12);
  });

  test('the upgrade leaves the existing groups alone', () async {
    final db = await openV11();

    await db.customSelect('SELECT 1').get();

    final groups = await db.customSelect('SELECT id, name, enabled, current, position FROM wallpaper_groups').get();
    expect(groups, hasLength(1));
    expect(groups.single.data['id'], 'wallpaper.group.all');
    expect(groups.single.data['enabled'], 1);
    expect(groups.single.data['current'], 1);
  });

  test('the history starts empty after the upgrade', () async {
    final db = await openV11();

    await db.customSelect('SELECT 1').get();

    expect(await GroupedWallpaperHistoryStore(db).load(), isEmpty);
  });

  test('a fresh database creates the table too', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await columnsOf(db, 'grouped_wallpaper_history'), contains('usedAt'));
  });
}
