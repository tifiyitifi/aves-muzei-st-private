import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';
import 'legacy_database.dart';

/// Schema v14 -> v15 adds the copy-first edit session tables.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v14 database gains the edit session and output tables', () async {
    final db = await openDatabaseAt(14, (seed) async {
      await seed.customStatement('DROP TABLE refra_edit_outputs');
      await seed.customStatement('DROP TABLE refra_edit_sessions');
    });

    final tables = await databaseObjects(db, 'table');
    expect(tables, containsAll(['refra_edit_sessions', 'refra_edit_outputs']));

    final indexes = await databaseObjects(db, 'index');
    expect(indexes, containsAll(['idx_refra_edit_sessions_created_at', 'idx_refra_edit_outputs_session']));

    await db.customStatement(
      'INSERT INTO refra_edit_sessions (id, sourceEntryId, sourceUri, sourcePath, sourceDirectory, sourceName, sourceMimeType, stagingDirectory, stagedUri, createdAt, status) '
      "VALUES ('s1', 1, 'content://media/1', '/dcim/1.jpg', '/dcim', '1.jpg', 'image/jpeg', '/pictures/staging', 'content://media/2', 1, 'active')",
    );
    final session = await db.customSelect("SELECT status FROM refra_edit_sessions WHERE id = 's1'").getSingle();
    expect(session.data['status'], 'active');
  });
}
