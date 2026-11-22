import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v12 -> v13 gives the history a surface and the group a separate lock
/// range.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v12 history row moves to the home surface', () async {
    final db = await openDatabaseAt(12, (seed) async {
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN separateLockRange');
      await seed.customStatement('DROP TABLE grouped_wallpaper_history');
      await seed.customStatement(
        'CREATE TABLE grouped_wallpaper_history ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'entryId INTEGER NOT NULL, '
        'groupId TEXT NOT NULL, '
        "groupName TEXT NOT NULL DEFAULT '', "
        'groupNumber INTEGER NOT NULL DEFAULT 0, '
        'usedAt INTEGER NOT NULL, '
        'UNIQUE (entryId, groupId))',
      );
      await seed.customStatement("INSERT INTO grouped_wallpaper_history (entryId, groupId, usedAt) VALUES (1, 'g1', 42)");
    });

    expect(await columnNames(db, 'wallpaper_groups'), contains('separateLockRange'));

    final row = await db.customSelect('SELECT entryId, groupId, surface FROM grouped_wallpaper_history').getSingle();
    expect(row.data['entryId'], 1);
    expect(row.data['groupId'], 'g1');
    expect(row.data['surface'], 'home', reason: 'every row before v13 belonged to the home surface');
  });
}
