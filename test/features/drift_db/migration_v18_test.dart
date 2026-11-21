import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v17 -> v18: the id-only index merged an image and a video that shared
/// a MediaStore number. The replacement index keeps them apart while still
/// rejecting a second report of the same file.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v17 database upgrades to v18 with a collection-aware identity', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, origin INTEGER, stackTileId INTEGER, sourceMimeType TEXT)');
          raw.execute(
            'CREATE UNIQUE INDEX idx_entry_media_store_content_id ON entry (contentId) '
            'WHERE contentId IS NOT NULL AND origin = ${EntryOrigins.mediaStoreContent}',
          );
          raw.execute('PRAGMA user_version = 17');
        },
      ),
    );
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final indexes = [
      for (final row in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'entry'").get()) row.data['name'] as String,
    ];
    expect(indexes, contains('idx_entry_media_store_identity'));
    expect(indexes, isNot(contains('idx_entry_media_store_content_id')));

    await db.customStatement(
      'INSERT INTO entry (id, contentId, uri, path, origin, sourceMimeType) VALUES '
      "(1, 501, 'content://media/external/images/media/501', '/a/1.jpg', ${EntryOrigins.mediaStoreContent}, 'image/jpeg')",
    );
    await db.customStatement(
      'INSERT INTO entry (id, contentId, uri, path, origin, sourceMimeType) VALUES '
      "(2, 501, 'content://media/external/video/media/501', '/a/1.mp4', ${EntryOrigins.mediaStoreContent}, 'video/mp4')",
    );

    expect(
      () => db.customStatement(
        'INSERT INTO entry (id, contentId, uri, path, origin, sourceMimeType) VALUES '
        "(3, 501, 'content://media/external/images/media/501', '/a/1.jpg', ${EntryOrigins.mediaStoreContent}, 'image/jpeg')",
      ),
      throwsA(predicate((error) => error.toString().contains('UNIQUE'))),
    );
  });
}
