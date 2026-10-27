import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v8 -> v9 adds the base activation flag without changing what existing
/// ranges mean.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v8 database gains the base activation flag as active', () async {
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
            'INSERT INTO visible_ranges (id, scope, ownerId, baseFilters, createdAt, updatedAt) '
            'VALUES (\'gallery\', \'gallery\', \'gallery\', \'[{"type":"favourite"}]\', 1, 2)',
          );
          raw.execute('PRAGMA user_version = 8');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(range, isNotNull);
    expect(range!.baseActive, isTrue);
    expect(range.isRestricted, isTrue);
  });

  test('a fresh database has the column and it defaults to active', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final columns = (await db.customSelect('PRAGMA table_info(visible_ranges)').get()).map((row) => row.data['name']).toSet();
    expect(columns, contains('baseActive'));

    final range = VisibleRange.emptyGallery(now: 1);
    await VisibleRangeStore(db).saveRange(range);
    final stored = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId);
    expect(stored!.baseActive, isTrue);
  });
}
