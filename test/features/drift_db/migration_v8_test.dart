import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v7 -> v8 adds the applied-rule target table, gives the group a
/// description, and drops the old session table.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v7 database gains the usage table and a described group', () async {
    final db = await openDatabaseAt(7, (seed) async {
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN description');
      await seed.customStatement('DROP TABLE visible_range_rule_usage');
      // A real v7 install still had the session history that v8 removes.
      await seed.customStatement('CREATE TABLE visible_range_sessions (id TEXT NOT NULL PRIMARY KEY)');
    });

    final tables = await databaseObjects(db, 'table');
    expect(tables, isNot(contains('visible_range_sessions')));
    expect(tables, contains('visible_range_rule_usage'));
    expect(await columnNames(db, 'wallpaper_groups'), contains('description'));

    await db.customStatement("INSERT INTO wallpaper_groups (id, createdAt, updatedAt) VALUES ('g1', 1, 2)");
    final row = await db.customSelect("SELECT description FROM wallpaper_groups WHERE id = 'g1'").getSingle();
    expect(row.data['description'], '');
  });
}
