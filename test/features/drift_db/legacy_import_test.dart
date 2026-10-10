import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/migration/legacy_import.dart';
import 'package:aves/model/db/db_sqflite_schema.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String legacyPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aves_drift_import_test');
    legacyPath = p.join(tempDir.path, LegacyImport.legacyDbFileName);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seedLegacy() async {
    final legacy = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (db, version) => SqfliteLocalMediaDbSchema.createLatestVersion(db),
      ),
    );
    final filterJson = StoredAlbumFilter('/album', null).toJsonString();
    await legacy.insert('entry', {
      'id': 1,
      'contentId': 100,
      'uri': 'content://1',
      'path': '/album/1.jpg',
      'sourceMimeType': 'image/jpeg',
      'width': 10,
      'height': 20,
      'sourceRotationDegrees': 0,
      'sizeBytes': 5,
      'title': 'one',
      'dateAddedSecs': 1,
      'dateModifiedMillis': 2,
      'sourceDateTakenMillis': 3,
      'durationMillis': 0,
      'trashed': 0,
      'origin': 0,
    });
    await legacy.insert('favourites', {'id': 1});
    await legacy.insert('metadata', {'id': 1, 'mimeType': 'image/jpeg', 'dateMillis': 3, 'flags': 0, 'rating': 4});
    await legacy.insert('dateTaken', {'id': 1, 'dateMillis': 3});
    await legacy.insert('covers', {'filter': filterJson, 'entryId': 1, 'packageName': null, 'color': null});
    await legacy.insert('dynamicAlbums', {'name': 'dyn', 'filter': filterJson});
    await legacy.insert('vaults', {'name': 'v', 'autoLock': 1, 'useBin': 0, 'lockType': 'system'});
    await legacy.insert('trash', {'id': 1, 'path': '/trash/1', 'dateMillis': 9});
    await legacy.insert('videoPlayback', {'id': 1, 'resumeTimeMillis': 42});
    await legacy.insert('debug', {'message': 'log'});
    await legacy.close();
  }

  Future<int> count(AppDatabase db, String table) async {
    final rows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
    return rows.first.data['c'] as int? ?? 0;
  }

  test('imports every legacy table, keeps a backup, and is idempotent', () async {
    await seedLegacy();

    final db = AppDatabase(NativeDatabase.memory());
    await LegacyImport(db, AppMetaStore(db)).runIfNeeded(legacyPath: legacyPath);

    for (final table in <String>['entry', 'favourites', 'metadata', 'dateTaken', 'covers', 'dynamicAlbums', 'vaults', 'trash', 'videoPlayback', 'debug']) {
      expect(await count(db, table), 1, reason: 'table=$table');
    }
    expect(await count(db, 'appMeta'), 1);

    // legacy file renamed to the rollback backup, not deleted
    expect(File(legacyPath).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, LegacyImport.importedBackupFileName)).existsSync(), isTrue);

    // second run is a no-op
    await LegacyImport(db, AppMetaStore(db)).runIfNeeded(legacyPath: legacyPath);
    expect(await count(db, 'entry'), 1);

    await db.close();
  });

  test('fresh install without a legacy file just marks the import done', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await LegacyImport(db, AppMetaStore(db)).runIfNeeded(legacyPath: legacyPath);

    expect(await count(db, 'appMeta'), 1);
    expect(await count(db, 'entry'), 0);

    await db.close();
  });
}
