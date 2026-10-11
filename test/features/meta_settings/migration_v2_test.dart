import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v1 database upgrades to v2 with the settings value table', () async {
    // Simulate an on-disk database still at schema version 1 (no settings table).
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 1'),
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.data['name']).toSet();
    expect(tables, contains('settingsValues'));

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, 2);
  });
}
