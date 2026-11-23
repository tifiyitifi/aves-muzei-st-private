import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v19 -> v20: the gallery's group 0 is the 「Unrestricted」 sentinel, so
/// the pre-release gallery groups and their locks are reset while the wallpaper
/// pools survive.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE visible_ranges ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'scope TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'ownerId TEXT NOT NULL, '
            "name TEXT NOT NULL DEFAULT '', "
            'position INTEGER NOT NULL DEFAULT 0, '
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
            'CREATE TABLE visible_range_rule_usage (id TEXT NOT NULL PRIMARY KEY, rangeId TEXT NOT NULL, targetId TEXT NOT NULL, kind TEXT NOT NULL, usedAt INTEGER NOT NULL)',
          );
          raw.execute('CREATE TABLE visible_range_state (key TEXT NOT NULL PRIMARY KEY, value TEXT)');
          raw.execute(
            'INSERT INTO visible_ranges (id, scope, kind, ownerId, name, position, locked, createdAt, updatedAt) VALUES '
            "('gallery', 'gallery', 'group', 'gallery', '', 0, 1, 1, 1), "
            "('group.1', 'gallery', 'group', 'group.1', 'Trips', 1, 0, 1, 1), "
            "('gallery.outside', 'gallery', 'outside', 'gallery.outside', '', 9999, 0, 1, 1), "
            "('g.range', 'wallpaper', 'group', 'g', '', 0, 0, 1, 1)",
          );
          raw.execute(
            'INSERT INTO visible_range_rules (id, rangeId, kind, position) VALUES '
            "('r-group', 'group.1', 'source', 0), "
            "('r-outside', 'gallery.outside', 'restriction', 0), "
            "('r-wall', 'g.range', 'restriction', 0)",
          );
          raw.execute("INSERT INTO visible_range_rule_usage (id, rangeId, targetId, kind, usedAt) VALUES ('rule.r-group', 'group.1', 'r-group', 'base', 1)");
          raw.execute("INSERT INTO visible_range_state (key, value) VALUES ('gallery.current', 'group.1'), ('defaults.version', '4')");
          raw.execute('PRAGMA user_version = 19');
        },
      ),
    );
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
  });

  test('resets the gallery scope and keeps the wallpaper pool', () async {
    final store = VisibleRangeStore(db);
    expect(await store.loadGroups(VisibleRangeScope.gallery), isEmpty);
    expect(await store.loadOutside(VisibleRangeScope.gallery), isNull);
    expect(await store.readState(VisibleRangeStore.keyCurrentGalleryGroupId), isNull);
    expect(await store.readState(VisibleRangeStore.keyDefaultsVersion), isNull);
    expect(await store.loadUsages(), isEmpty);

    final wallpaper = await store.loadRange(scope: VisibleRangeScope.wallpaper, ownerId: 'g');
    expect(wallpaper, isNotNull);
    expect(wallpaper!.ruleById('r-wall'), isNotNull);
  });
}
