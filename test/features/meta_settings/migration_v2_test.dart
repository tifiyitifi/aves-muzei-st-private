import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v1 database upgrades to the current schema with the settings value table', () async {
    // Simulate an on-disk v1 database: it has the app tables but no
    // `settingsValues` table yet. Later migrations (v3) still run, so the
    // tables they touch must exist, as they would on a real device.
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, sourceMimeType TEXT, width INTEGER, height INTEGER, sourceRotationDegrees INTEGER, sizeBytes INTEGER, title TEXT, dateAddedSecs INTEGER, dateModifiedMillis INTEGER, sourceDateTakenMillis INTEGER, durationMillis INTEGER, trashed INTEGER, origin INTEGER)');
          raw.execute('CREATE TABLE dateTaken (id INTEGER NOT NULL PRIMARY KEY, dateMillis INTEGER)');
          raw.execute('CREATE TABLE metadata (id INTEGER NOT NULL PRIMARY KEY, mimeType TEXT, dateMillis INTEGER, flags INTEGER, rotationDegrees INTEGER, xmpSubjects TEXT, xmpTitle TEXT, latitude REAL, longitude REAL, rating INTEGER)');
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.data['name']).toSet();
    expect(tables, contains('settingsValues'));

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, greaterThanOrEqualTo(2));
  });
}
