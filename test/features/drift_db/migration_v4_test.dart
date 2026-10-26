import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Schema v3 -> v4: the stack index columns are added, `baseName` and `stackKey`
/// are backfilled from `path`, and `stackTileId` is settled per stack group.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    settings.collectionBurstPatterns = [BurstPatterns.samsung];
  });

  tearDownAll(getIt.reset);

  test('a v3 database upgrades to v4 with the stack index filled', () async {
    // Simulate an on-disk database still at schema version 3 (a `directory`
    // column, no stack columns).
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, sourceMimeType TEXT, width INTEGER, height INTEGER, sourceRotationDegrees INTEGER, sizeBytes INTEGER, title TEXT, dateAddedSecs INTEGER, dateModifiedMillis INTEGER, sourceDateTakenMillis INTEGER, durationMillis INTEGER, trashed INTEGER, origin INTEGER, directory TEXT)',
          );
          raw.execute('CREATE TABLE dateTaken (id INTEGER NOT NULL PRIMARY KEY, dateMillis INTEGER)');
          raw.execute('CREATE TABLE metadata (id INTEGER NOT NULL PRIMARY KEY, mimeType TEXT, dateMillis INTEGER, flags INTEGER, rotationDegrees INTEGER, xmpSubjects TEXT, xmpTitle TEXT, latitude REAL, longitude REAL, rating INTEGER)');
          // A burst group (the samsung pattern keys it by `yyyyMMdd_HHmmss`), a
          // developed-raw pair, and a path-less row.
          raw.execute(
            'INSERT INTO entry (id, path, directory, sourceMimeType) VALUES '
            "(1, '/cam/20151021_072800_001.jpg', '/cam', 'image/jpeg'), "
            "(2, '/cam/20151021_072800_002.jpg', '/cam', 'image/jpeg'), "
            "(3, '/cam/IMG_1.jpg', '/cam', 'image/jpeg'), "
            "(4, '/cam/IMG_1.dng', '/cam', '${MimeTypes.dng}'), "
            '(5, NULL, NULL, NULL)',
          );
          raw.execute('PRAGMA user_version = 3');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final rows = await db.customSelect('SELECT id, baseName, stackKey, stackTileId FROM entry ORDER BY id').get();
    final byId = {for (final row in rows) row.data['id'] as int: row.data};
    expect(byId[1]!['baseName'], '20151021_072800_001');
    expect(byId[1]!['stackKey'], '/cam/20151021_072800');
    expect(byId[5]!['baseName'], null);
    expect(byId[5]!['stackKey'], null);

    // A burst tile shows itself, its frames point at it; the path-less row is in
    // no group.
    expect(byId[1]!['stackTileId'], null);
    expect(byId[2]!['stackTileId'], 1);
    expect(byId[5]!['stackTileId'], null);

    // The developed image of a pair shows itself and hides the raw.
    expect(byId[3]!['stackTileId'], null);
    expect(byId[4]!['stackTileId'], 3);

    final indexes = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get()).map((r) => r.data['name']).toSet();
    expect(
      indexes,
      containsAll([
        'idx_entry_stackKey',
        'idx_entry_directory_baseName',
        'idx_entry_stackTileId',
      ]),
    );
  });
}
