import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v12 -> v13 adds the split lock surface and the surface of a history row.
void main() {
  setUpAll(ensureSqlite3Loaded);

  /// A v12 database: groups without `separateLockRange`, history without
  /// `surface` and keyed by `(entryId, groupId)`.
  Future<AppDatabase> openV12() async {
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
            "VALUES ('group.1', 'A', 1, 1, 0, 1, 2)",
          );
          raw.execute(
            'CREATE TABLE grouped_wallpaper_history ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'entryId INTEGER NOT NULL, '
            'groupId TEXT NOT NULL, '
            "groupName TEXT NOT NULL DEFAULT '', "
            'groupNumber INTEGER NOT NULL DEFAULT 0, '
            'usedAt INTEGER NOT NULL, '
            'UNIQUE (entryId, groupId))',
          );
          raw.execute(
            'INSERT INTO grouped_wallpaper_history (entryId, groupId, groupName, groupNumber, usedAt) '
            "VALUES (7, 'group.1', 'A', 1, 100), (8, 'group.1', 'A', 1, 101)",
          );
          raw.execute('PRAGMA user_version = 12');
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

  test('a v12 database gains the split column, the surface and the new key', () async {
    final db = await openV12();

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    expect(await columnsOf(db, 'wallpaper_groups'), contains('separateLockRange'));
    expect(await columnsOf(db, 'grouped_wallpaper_history'), contains('surface'));

    final groups = await db.customSelect('SELECT id, separateLockRange FROM wallpaper_groups').get();
    expect(groups.single.data['separateLockRange'], 0);

    final rows = await db.customSelect('SELECT entryId, surface, usedAt FROM grouped_wallpaper_history ORDER BY entryId').get();
    expect([for (final row in rows) row.data['surface']], ['home', 'home']);
    expect([for (final row in rows) row.data['usedAt']], [100, 101]);

    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_grouped_wallpaper_history_used_at'").get();
    expect(indexes, hasLength(1));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });

  test('the rebuilt key keeps home and lock rows apart', () async {
    final db = await openV12();
    await db.customSelect('SELECT 1').get();

    Future<void> insert(String surface, int usedAt) => db.into(db.groupedWallpaperHistoryRows).insert(
          GroupedWallpaperHistoryRowsCompanion.insert(
            entryId: 9,
            groupId: 'group.1',
            usedAt: usedAt,
            surface: Value(surface),
          ),
          mode: InsertMode.insertOrReplace,
        );

    await insert('home', 200);
    await insert('lock', 201);
    final rows = await db.customSelect('SELECT surface FROM grouped_wallpaper_history WHERE entryId = 9 ORDER BY usedAt').get();
    expect([for (final row in rows) row.data['surface']], ['home', 'lock']);
  });
}
