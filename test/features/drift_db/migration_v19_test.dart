import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v18 -> v19: a wallpaper base becomes a `source` rule. The gallery
/// scope is reset by v20 (group 0 is the 「Unrestricted」 sentinel), so this test
/// keeps its fixture on a wallpaper pool to observe the v19 mapping itself.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;

  setUp(() async {
    final imageJson = VisibleRangeFilterCodec.encode({MimeFilter.image});
    final favouriteJson = VisibleRangeFilterCodec.encode({FavouriteFilter.instance});
    db = AppDatabase(
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
            'baseActive INTEGER NOT NULL DEFAULT 1, '
            'baseSurfaces INTEGER NOT NULL DEFAULT 0, '
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
            'active INTEGER NOT NULL DEFAULT 1, '
            'surfaces INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(
            'CREATE TABLE visible_range_presets ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'name TEXT NOT NULL, '
            "description TEXT NOT NULL DEFAULT '', "
            "filters TEXT NOT NULL DEFAULT '[]', "
            'builtin INTEGER NOT NULL DEFAULT 0, '
            'position INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute('CREATE TABLE visible_range_rule_usage (id TEXT NOT NULL PRIMARY KEY, rangeId TEXT NOT NULL, targetId TEXT NOT NULL, kind TEXT NOT NULL, usedAt INTEGER NOT NULL)');
          raw.execute('CREATE TABLE visible_range_state (key TEXT NOT NULL PRIMARY KEY, value TEXT)');
          raw.execute(
            'INSERT INTO visible_ranges (id, scope, ownerId, baseName, basePresetId, baseFilters, baseActive, baseSurfaces, createdAt, updatedAt) '
            "VALUES ('g.range', 'wallpaper', 'g', '@wallpaperGroupDefaultDcim', '', ?, 1, 3, 1, 2)",
            [imageJson],
          );
          raw.execute(
            'INSERT INTO visible_range_presets (id, name, filters, builtin, position) VALUES (?, ?, ?, 1, 0)',
            ['builtin.image', '@visibleRangePresetImage', imageJson],
          );
          raw.execute(
            'INSERT INTO visible_range_rules (id, rangeId, kind, position, filters) VALUES (?, ?, ?, 0, ?)',
            ['r1', 'g.range', 'restriction', favouriteJson],
          );
          raw.execute('INSERT INTO visible_range_rule_usage (id, rangeId, targetId, kind, usedAt) VALUES (?, ?, ?, ?, 1)', ['rule.r1', 'g.range', 'r1', 'restriction']);
          raw.execute('PRAGMA user_version = 18');
        },
      ),
    );
    addTearDown(db.close);
    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();
  });

  test('upgrades to the visibility-group shape', () async {
    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    // The legacy columns stay one release for a rollback.
    final columns = (await db.customSelect('PRAGMA table_info(visible_ranges)').get()).map((row) => row.data['name']).toSet();
    expect(columns, containsAll(['baseFilters', 'kind', 'name', 'position']));
  });

  test('a wallpaper base becomes a source condition and keeps its rules', () async {
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'g');
    expect(range, isNotNull);
    expect(range!.rulesOf(VisibleRangeRuleKind.source).single.filters, {MimeFilter.image});
    expect(range.ruleById('r1')!.filters, {FavouriteFilter.instance});
    expect(range.baseSurfaces, 3);
    expect((await VisibleRangeStore(db).loadUsages()).single.targetId, 'r1');
  });

  test('the gallery scope is reset by v20', () async {
    final store = VisibleRangeStore(db);
    expect(await store.loadGroups(VisibleRangeScope.gallery), isEmpty);
    expect(await store.readState(VisibleRangeStore.keyCurrentGalleryGroupId), isNull);
  });
}
