import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// Schema v15 -> v16: a file reported twice used to take a second row, and two
/// rows sharing a media-store id end up as two tiles with the same hero tag. The
/// migration merges them into the oldest row and makes a repeated report a
/// no-op.
void main() {
  setUpAll(ensureSqlite3Loaded);

  test('a v15 database upgrades to v16 with the duplicate rows merged', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, origin INTEGER, stackTileId INTEGER)');
          raw.execute('CREATE TABLE dateTaken (id INTEGER NOT NULL PRIMARY KEY, dateMillis INTEGER)');
          raw.execute('CREATE TABLE metadata (id INTEGER NOT NULL PRIMARY KEY, mimeType TEXT, rating INTEGER)');
          raw.execute('CREATE TABLE address (id INTEGER NOT NULL PRIMARY KEY, addressLine TEXT)');
          raw.execute('CREATE TABLE favourites (id INTEGER NOT NULL PRIMARY KEY)');
          raw.execute('CREATE TABLE trash (id INTEGER NOT NULL PRIMARY KEY, path TEXT)');
          raw.execute('CREATE TABLE videoPlayback (id INTEGER NOT NULL PRIMARY KEY, resumeTimeMillis INTEGER)');
          raw.execute('CREATE TABLE covers (filter TEXT NOT NULL PRIMARY KEY, entryId INTEGER, packageName TEXT, color TEXT)');

          // Three reports of one file, plus a live row, a vault row sharing the
          // same content id (a different origin, so a different identity) and a
          // row with no content id.
          raw.execute(
            'INSERT INTO entry (id, contentId, uri, path, origin) VALUES '
            "(10, 501, 'content://media/external/images/media/501', '/a/1.jpg', ${EntryOrigins.mediaStoreContent}), "
            "(11, 501, 'content://media/external/images/media/501', '/a/1.jpg', ${EntryOrigins.mediaStoreContent}), "
            "(12, 501, 'content://media/external_primary/images/media/501', '/a/1.jpg', ${EntryOrigins.mediaStoreContent}), "
            '(13, 502, NULL, NULL, ${EntryOrigins.mediaStoreContent}), '
            "(14, 502, 'file:///vault/1.jpg', '/vault/1.jpg', ${EntryOrigins.vault}), "
            '(15, NULL, NULL, NULL, ${EntryOrigins.mediaStoreContent})',
          );
          raw.execute('UPDATE entry SET stackTileId = 12 WHERE id = 15');

          // References the dropped rows carry.
          raw.execute('INSERT INTO favourites (id) VALUES (11), (10)');
          raw.execute('INSERT INTO dateTaken (id, dateMillis) VALUES (11, 999), (10, 111)');
          raw.execute("INSERT INTO metadata (id, mimeType, rating) VALUES (12, 'image/jpeg', 5)");
          raw.execute("INSERT INTO covers (filter, entryId) VALUES ('album:/a', 12)");
          raw.execute('PRAGMA user_version = 15');
        },
      ),
    );
    addTearDown(db.close);

    // Force the connection open so the migration runs.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').get()).single.data['user_version'];
    expect(version, db.schemaVersion);

    final rows = await db.customSelect('SELECT id, contentId, origin FROM entry ORDER BY id').get();
    expect([for (final row in rows) row.data['id']], [10, 13, 14, 15]);
    expect(rows.where((row) => row.data['contentId'] == 501).length, 1);

    // Everything that pointed at a dropped row now points at the survivor.
    expect((await db.customSelect('SELECT id FROM favourites ORDER BY id').get()).map((row) => row.data['id']), [10]);
    expect((await db.customSelect('SELECT dateMillis FROM dateTaken WHERE id = 10').get()).single.data['dateMillis'], 111);
    expect((await db.customSelect('SELECT entryId FROM covers').get()).single.data['entryId'], 10);
    expect((await db.customSelect('SELECT stackTileId FROM entry WHERE id = 15').get()).single.data['stackTileId'], 10);
    // The survivor already had a date, so the dropped one is gone rather than
    // overwriting it.
    expect((await db.customSelect('SELECT id FROM dateTaken WHERE id != 10').get()), isEmpty);
  });

  test('the media store identity is unique after the upgrade', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE entry (id INTEGER NOT NULL PRIMARY KEY, contentId INTEGER, uri TEXT, path TEXT, origin INTEGER, stackTileId INTEGER)');
          raw.execute('PRAGMA user_version = 15');
        },
      ),
    );
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    await db.customStatement(
      'INSERT INTO entry (id, contentId, origin) VALUES (1, 501, ${EntryOrigins.mediaStoreContent})',
    );

    // A second report of the same file is rejected by the index, and the writer
    // turns that into a no-op insert instead of a second row.
    expect(
      () => db.customStatement('INSERT INTO entry (id, contentId, origin) VALUES (2, 501, ${EntryOrigins.mediaStoreContent})'),
      throwsA(predicate((error) => error.toString().contains('UNIQUE'))),
    );
  });
}
