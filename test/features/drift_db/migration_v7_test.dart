import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v6 -> v7 adds the wallpaper-group table.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v6 database gains the wallpaper-group table and its index', () async {
    final db = await openDatabaseAt(6, (seed) async {
      await seed.customStatement('DROP TABLE wallpaper_groups');
    });

    expect(await databaseObjects(db, 'table'), contains('wallpaper_groups'));
    expect(await databaseObjects(db, 'index'), contains('idx_wallpaper_groups_position'));

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);
  });
}
