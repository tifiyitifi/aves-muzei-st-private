import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Schema v13 -> v14 folds each group's lock range into one condition pool.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  String filters(Iterable<Object> values) => VisibleRangeFilterCodec.encode(values.cast());

  /// A v13 database: one range row per surface, no surface marks, no
  /// `lockRangeSeeded`.
  Future<AppDatabase> openV13() async {
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
            "ordering TEXT NOT NULL DEFAULT 'newThenRandom', "
            'separateLockRange INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(
            'CREATE TABLE visible_ranges ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'scope TEXT NOT NULL, '
            'ownerId TEXT NOT NULL, '
            "baseName TEXT NOT NULL DEFAULT '', "
            "basePresetId TEXT NOT NULL DEFAULT '', "
            "baseFilters TEXT NOT NULL DEFAULT '[]', "
            'baseActive INTEGER NOT NULL DEFAULT 1, '
            "orderMode TEXT NOT NULL DEFAULT 'intersectFirst', "
            'locked INTEGER NOT NULL DEFAULT 0, '
            'permissions TEXT, '
            'createdAt INTEGER NOT NULL, '
            'updatedAt INTEGER NOT NULL)',
          );
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
          raw.execute(
            'CREATE TABLE visible_range_rule_usage ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'rangeId TEXT NOT NULL, '
            "targetId TEXT NOT NULL DEFAULT '', "
            'kind TEXT NOT NULL, '
            'usedAt INTEGER NOT NULL)',
          );
          raw.execute(
            'INSERT INTO wallpaper_groups (id, name, enabled, current, position, createdAt, updatedAt, separateLockRange) VALUES '
            "('g1', 'A', 1, 1, 0, 1, 2, 1), ('g2', 'B', 1, 0, 1, 1, 2, 1), ('g3', 'C', 1, 0, 2, 1, 2, 0)",
          );
          // g1: same base and one identical rule, one home-only inactive rule,
          // one lock-only rule.
          raw.execute(
            'INSERT INTO visible_ranges (id, scope, ownerId, baseName, baseFilters, baseActive, createdAt, updatedAt) VALUES '
            "('g1.range', 'wallpaper', 'g1', 'DCIM', ?, 1, 1, 2), "
            "('g1.lock.range', 'wallpaper', 'g1.lock', 'DCIM', ?, 1, 1, 2)",
            [
              filters({PathFilter('/dcim')}),
              filters({PathFilter('/dcim')}),
            ],
          );
          raw.execute(
            'INSERT INTO visible_range_rules (id, rangeId, kind, position, label, filters, active) VALUES '
            "('r-shared', 'g1.range', 'restriction', 0, 'Images', ?, 1), "
            "('r-home', 'g1.range', 'supplement', 0, 'Home only', ?, 0), "
            "('l-shared', 'g1.lock.range', 'restriction', 0, 'Images', ?, 1), "
            "('l-lock', 'g1.lock.range', 'restriction', 1, 'Videos', ?, 1)",
            [
              filters({MimeFilter.image}),
              filters({MimeFilter.image}),
              filters({MimeFilter.image}),
              filters({MimeFilter.video}),
            ],
          );
          raw.execute(
            'INSERT INTO visible_range_rule_usage (id, rangeId, targetId, kind, usedAt) VALUES '
            "('base.g1.lock.range', 'g1.lock.range', '', 'base', 10), "
            "('rule.l-lock', 'g1.lock.range', 'l-lock', 'restriction', 11)",
          );
          // g2: different bases, so the lock one becomes a lock-only restriction.
          raw.execute(
            'INSERT INTO visible_ranges (id, scope, ownerId, baseName, baseFilters, baseActive, createdAt, updatedAt) VALUES '
            "('g2.range', 'wallpaper', 'g2', 'Pictures', ?, 1, 1, 2), "
            "('g2.lock.range', 'wallpaper', 'g2.lock', 'DCIM', ?, 1, 1, 2)",
            [
              filters({PathFilter('/pictures')}),
              filters({PathFilter('/dcim')}),
            ],
          );
          raw.execute('PRAGMA user_version = 13');
        },
      ),
    );
    addTearDown(db.close);
    return db;
  }

  test('the columns are added and the version moves to the current schema', () async {
    final db = await openV13();
    await db.customSelect('SELECT 1').get();

    final rangeColumns = await db.customSelect('PRAGMA table_info(visible_ranges)').get();
    expect({for (final row in rangeColumns) row.data['name']}, contains('baseSurfaces'));
    final ruleColumns = await db.customSelect('PRAGMA table_info(visible_range_rules)').get();
    expect({for (final row in ruleColumns) row.data['name']}, contains('surfaces'));
    final groupColumns = await db.customSelect('PRAGMA table_info(wallpaper_groups)').get();
    expect({for (final row in groupColumns) row.data['name']}, contains('lockRangeSeeded'));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);
  });

  test('identical conditions merge into one row marked for both surfaces', () async {
    final db = await openV13();
    await db.customSelect('SELECT 1').get();

    final ranges = await db.customSelect("SELECT id, baseSurfaces FROM visible_ranges WHERE ownerId = 'g1'").get();
    expect(ranges, hasLength(1));
    expect(ranges.single.data['id'], 'g1.range');
    expect(ranges.single.data['baseSurfaces'], WallpaperConditionSurfaces.all);

    final rules = await db.customSelect("SELECT id, surfaces, active FROM visible_range_rules WHERE rangeId = 'g1.range' ORDER BY id").get();
    final byId = {for (final row in rules) row.data['id']: row.data['surfaces']};
    expect(byId['r-shared'], WallpaperConditionSurfaces.all);
    expect(byId['r-home'], 0);
    expect(byId['l-lock'], WallpaperConditionSurfaces.lock);
    expect(byId.containsKey('l-shared'), isFalse);
    // Every wallpaper condition is stored with the mark as its only switch.
    expect(rules.every((row) => row.data['active'] == 1 || row.data['active'] == true), isTrue);

    final groups = await db.customSelect('SELECT id, lockRangeSeeded FROM wallpaper_groups ORDER BY id').get();
    expect([for (final row in groups) row.data['lockRangeSeeded']], [1, 1, 0]);

    // The lock range no longer exists.
    expect(await db.customSelect("SELECT id FROM visible_ranges WHERE id LIKE 'g1.lock%'").get(), isEmpty);
  });

  test('a lock-only base becomes a lock-only restriction', () async {
    final db = await openV13();
    await db.customSelect('SELECT 1').get();

    final range = await db.customSelect("SELECT baseFilters, baseSurfaces FROM visible_ranges WHERE id = 'g2.range'").getSingle();
    expect(range.data['baseSurfaces'], WallpaperConditionSurfaces.home);
    expect(VisibleRangeFilterCodec.decode(range.data['baseFilters']), {PathFilter('/pictures')});

    final rule = await db.customSelect("SELECT kind, filters, surfaces FROM visible_range_rules WHERE id = 'migrated.g2.lockbase'").getSingle();
    expect(rule.data['kind'], 'restriction');
    expect(rule.data['surfaces'], WallpaperConditionSurfaces.lock);
    // Same range: an unrestricted base AND the old base is the old lock range.
    expect(VisibleRangeFilterCodec.decode(rule.data['filters']), {PathFilter('/dcim')});
  });

  test('applied targets follow their condition into the pool', () async {
    final db = await openV13();
    await db.customSelect('SELECT 1').get();

    final rows = await db.customSelect('SELECT id, rangeId, targetId FROM visible_range_rule_usage ORDER BY id').get();
    expect([for (final row in rows) row.data['id']], ['base.g1.range', 'rule.l-lock']);
    expect(rows.every((row) => row.data['rangeId'] == 'g1.range'), isTrue);
  });
}
