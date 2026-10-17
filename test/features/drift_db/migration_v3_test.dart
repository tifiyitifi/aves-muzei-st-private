import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Schema v2 -> v3: the maintained `entry.directory` column is added,
/// backfilled from `path`, and covered by the v3 index set.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    // `pContext` (used by the directory backfill) is resolved from GetIt;
    // tests force a POSIX context so path handling matches the app.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  test('a v2 database upgrades to v3 with directories backfilled and indexed', () async {
    // Simulate an on-disk database still at schema version 2 (no `directory`
    // column): only the tables the v3 migration touches are created.
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, sourceMimeType TEXT, width INTEGER, height INTEGER, sourceRotationDegrees INTEGER, sizeBytes INTEGER, title TEXT, dateAddedSecs INTEGER, dateModifiedMillis INTEGER, sourceDateTakenMillis INTEGER, durationMillis INTEGER, trashed INTEGER, origin INTEGER)');
          raw.execute('CREATE TABLE dateTaken (id INTEGER NOT NULL PRIMARY KEY, dateMillis INTEGER)');
          raw.execute('CREATE TABLE metadata (id INTEGER NOT NULL PRIMARY KEY, mimeType TEXT, dateMillis INTEGER, flags INTEGER, rotationDegrees INTEGER, xmpSubjects TEXT, xmpTitle TEXT, latitude REAL, longitude REAL, rating INTEGER)');
          raw.execute("INSERT INTO entry (id, path) VALUES (1, '/a/1.jpg'), (2, '/a/b/2.jpg'), (3, NULL)");
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    // The chain is forward-only, so a v2 database lands on the current version;
    // what this test pins is that the v3 column/index work still happens.
    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, 4);

    final rows = await db.customSelect('SELECT id, directory FROM entry ORDER BY id').get();
    expect(rows.map((r) => r.data['directory']).toList(), ['/a', '/a/b', null]);

    final indexes = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get()).map((r) => r.data['name']).toSet();
    expect(
      indexes,
      containsAll([
        'idx_entry_origin_trashed',
        'idx_entry_directory',
        'idx_entry_sourceDateTaken',
        'idx_dateTaken_dateMillis',
        'idx_metadata_rating',
      ]),
    );
  });
}
