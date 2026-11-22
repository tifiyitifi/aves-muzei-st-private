import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v11 -> v12 adds the grouped wallpaper's usage history.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v11 database gains the history table and its index', () async {
    final db = await openDatabaseAt(11, (seed) async {
      await seed.customStatement('DROP TABLE grouped_wallpaper_history');
    });

    expect(await databaseObjects(db, 'table'), contains('grouped_wallpaper_history'));
    expect(await databaseObjects(db, 'index'), contains('idx_grouped_wallpaper_history_used_at'));

    await db.customStatement("INSERT INTO grouped_wallpaper_history (entryId, groupId, usedAt) VALUES (1, 'g1', 42)");
    final row = await db.customSelect('SELECT groupName, groupNumber, surface FROM grouped_wallpaper_history').getSingle();
    expect(row.data['groupName'], '');
    expect(row.data['groupNumber'], 0);
    expect(row.data['surface'], 'home');
  });
}
