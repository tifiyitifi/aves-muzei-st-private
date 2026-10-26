import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v4 -> v5 adds the visible-range tables and their indexes.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v4 database upgrades to v5 with the visible-range tables', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 4'),
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((row) => row.data['name']).toSet();
    expect(
      tables,
      containsAll([
        'visible_ranges',
        'visible_range_rules',
        'visible_range_sessions',
        'visible_range_presets',
        'visible_range_state',
      ]),
    );

    final indexes = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get()).map((row) => row.data['name']).toSet();
    expect(
      indexes,
      containsAll([
        'idx_visible_range_rules_rangeId',
        'idx_visible_range_sessions_rangeId',
        'idx_visible_ranges_scope_owner',
      ]),
    );
  });

  test('a fresh database creates the visible-range tables too', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.visibleRangeRows).get(), isEmpty);
    expect(await db.select(db.visibleRangeRuleRows).get(), isEmpty);
    expect(await db.select(db.visibleRangeSessionRows).get(), isEmpty);
    expect(await db.select(db.visibleRangePresetRows).get(), isEmpty);
    expect(await db.select(db.visibleRangeKeyValues).get(), isEmpty);
  });
}
