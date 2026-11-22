import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v9 -> v10 gives every wallpaper group its per-surface effects.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v9 database gains the effects column as the identity', () async {
    final db = await openDatabaseAt(9, (seed) async {
      await seed.customStatement('ALTER TABLE wallpaper_groups DROP COLUMN effects');
      await seed.customStatement("INSERT INTO wallpaper_groups (id, createdAt, updatedAt) VALUES ('g1', 1, 2)");
    });

    expect(await columnNames(db, 'wallpaper_groups'), contains('effects'));
    final row = await db.customSelect("SELECT effects FROM wallpaper_groups WHERE id = 'g1'").getSingle();
    // `{}` is the identity configuration: an upgraded group keeps its photos.
    expect(row.data['effects'], '{}');
  });
}
