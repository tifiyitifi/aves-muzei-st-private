import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v18 -> v19: the single gallery range becomes visibility groups, its
/// base becomes a `source` rule, and its old global rules move to the shared
/// outside pool. Wallpaper pools keep their ids.
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
            "VALUES ('gallery', 'gallery', 'gallery', '@visibleRangePresetImage', 'builtin.image', ?, 1, 0, 1, 2)",
            [imageJson],
          );
          raw.execute(
            'INSERT INTO visible_range_presets (id, name, filters, builtin, position) VALUES (?, ?, ?, 1, 0)',
            ['builtin.image', '@visibleRangePresetImage', imageJson],
          );
          raw.execute(
            'INSERT INTO visible_range_rules (id, rangeId, kind, position, filters) VALUES (?, ?, ?, 0, ?)',
            ['r1', 'gallery', 'restriction', favouriteJson],
          );
          raw.execute('INSERT INTO visible_range_rule_usage (id, rangeId, targetId, kind, usedAt) VALUES (?, ?, ?, ?, 1)', ['rule.r1', 'gallery', 'r1', 'restriction']);
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

  test('the preset-backed base becomes a group and the old rules move outside', () async {
    final store = VisibleRangeStore(db);
    final groups = await store.loadGroups(VisibleRangeScope.gallery);
    expect(groups.map((group) => group.id), containsAll(['gallery', 'builtin.group.builtin.image']));

    // The old base pointed at the preset, so that group is current and carries
    // the source; the gallery row is the unrestricted default.
    expect(await store.readState(VisibleRangeStore.keyCurrentGalleryGroupId), 'builtin.group.builtin.image');
    final presetGroup = groups.singleWhere((group) => group.id == 'builtin.group.builtin.image');
    expect(presetGroup.rulesOf(VisibleRangeRuleKind.source).single.filters, {MimeFilter.image});
    expect(groups.singleWhere((group) => group.id == 'gallery').rules, isEmpty);

    // The scope-wide rule kept its id and moved to the outside pool.
    final outside = await store.loadOutside(VisibleRangeScope.gallery);
    expect(outside, isNotNull);
    expect(outside!.kind, VisibleRangeGroupKind.outside);
    expect(outside.rules.single.id, 'r1');
    expect((await store.loadUsages()).single.rangeId, outside.id);
  });
}
