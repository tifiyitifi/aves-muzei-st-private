import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v10 -> v11 moves auto-advance onto the group and adopts the previous
/// global ordering value.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v10 database adopts the global ordering and gains the interval', () async {
    final db = await openDatabaseAt(10, (seed) async {
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN interval');
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN ordering');
      await seed.customStatement("INSERT INTO wallpaper_groups (id, createdAt, updatedAt) VALUES ('g1', 1, 2)");
      await seed.customStatement("INSERT INTO appMeta (key, value) VALUES ('wallpaper.groupedOrdering', 'random')");
    });

    final row = await db.customSelect("SELECT interval, ordering FROM wallpaper_groups WHERE id = 'g1'").getSingle();
    expect(row.data['interval'], 0, reason: 'off is the default');
    expect(row.data['ordering'], 'random', reason: 'the pre-v11 global choice moves into every group');

    final migrated = await db.customSelect("SELECT value FROM appMeta WHERE key = 'wallpaper.groupedOrdering'").get();
    expect(migrated, isEmpty, reason: 'the global key is dropped after adoption');
  });
}
