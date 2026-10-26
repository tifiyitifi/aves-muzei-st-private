import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v5 -> v6 adds the user-editable description to presets and rules.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v5 database upgrades to v6 with empty descriptions', () async {
    // Simulate a v5 database: the two affected tables without `description`,
    // holding rows created before the column existed.
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE visible_range_presets ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'name TEXT NOT NULL, '
            "filters TEXT NOT NULL DEFAULT '[]', "
            'builtin INTEGER NOT NULL DEFAULT 0, '
            'position INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(
            'CREATE TABLE visible_range_rules ('
            'id TEXT NOT NULL PRIMARY KEY, '
            'rangeId TEXT NOT NULL, '
            'kind TEXT NOT NULL, '
            'position INTEGER NOT NULL DEFAULT 0, '
            "label TEXT NOT NULL DEFAULT '', "
            "filters TEXT NOT NULL DEFAULT '[]', "
            'active INTEGER NOT NULL DEFAULT 1)',
          );
          raw.execute("INSERT INTO visible_range_presets (id, name) VALUES ('builtin.image', 'visibleRangePresetImage')");
          raw.execute("INSERT INTO visible_range_rules (id, rangeId, kind, label) VALUES ('r1', 'gallery', 'restriction', 'mine')");
          raw.execute('PRAGMA user_version = 5');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final presets = await db.select(db.visibleRangePresetRows).get();
    expect(presets, hasLength(1));
    expect(presets.single.name, 'visibleRangePresetImage');
    expect(presets.single.description, isEmpty);

    final rules = await db.select(db.visibleRangeRuleRows).get();
    expect(rules, hasLength(1));
    expect(rules.single.label, 'mine');
    expect(rules.single.description, isEmpty);
  });

  test('a fresh database has the description columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.visibleRangePresetRows).insert(
          VisibleRangePresetRowsCompanion.insert(id: 'p', name: 'n', description: const Value('note')),
        );
    final preset = (await db.select(db.visibleRangePresetRows).getSingle());
    expect(preset.description, 'note');
  });
}
