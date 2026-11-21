import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v16 -> v17 adds the batch result and profile tables.
///
/// Batch processing never touches an original, so the results folder alone
/// cannot say which source a copy came from; the migration gives the feature the
/// bookkeeping it needs without touching any existing row.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v16 database upgrades to v17 with the batch tables and indexes', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, sourceMimeType TEXT, origin INTEGER)');
          raw.execute('PRAGMA user_version = 16');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    final tableNames = {for (final row in tables) row.data['name'] as String};
    expect(tableNames, containsAll(['batch_results', 'batch_profiles']));

    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
    final indexNames = {for (final row in indexes) row.data['name'] as String};
    expect(
      indexNames,
      containsAll([
        'idx_batch_results_source_uri',
        'idx_batch_results_status',
        'idx_batch_results_created_at',
        'idx_batch_profiles_kind',
      ]),
    );
  });

  test('a fresh v17 database has the same tables and indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    final tableNames = {for (final row in tables) row.data['name'] as String};
    expect(tableNames, containsAll(['batch_results', 'batch_profiles']));

    final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
    final indexNames = {for (final row in indexes) row.data['name'] as String};
    expect(indexNames, containsAll(['idx_batch_results_source_uri', 'idx_batch_profiles_kind']));
  });
}
