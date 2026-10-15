import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/migration/legacy_import.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/features/drift_db/migration/legacy_import_state_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
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

  Future<void> seedLegacy({int entryCount = 1}) async {
    final legacy = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 16,
        onCreate: (db, version) => SqfliteLocalMediaDbSchema.createLatestVersion(db),
      ),
    );
    final filterJson = StoredAlbumFilter('/album', null).toJsonString();
    for (var id = 1; id <= entryCount; id++) {
      await legacy.insert('entry', {
        'id': id,
        'contentId': 100 + id,
        'uri': 'content://$id',
        'path': '/album/$id.jpg',
        'sourceMimeType': 'image/jpeg',
        'width': 10,
        'height': 20,
        'sourceRotationDegrees': 0,
        'sizeBytes': 5,
        'title': 'title$id',
        'dateAddedSecs': 1,
        'dateModifiedMillis': 2,
        'sourceDateTakenMillis': 3,
        'durationMillis': 0,
        'trashed': 0,
        'origin': 0,
      });
    }
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

  Future<LegacyImportStatus> status(AppDatabase db) => LegacyImportStateStore(AppMetaStore(db)).read().then((s) => s.status);

  test('imports every legacy table, keeps a backup, and is idempotent', () async {
    await seedLegacy();

    final db = AppDatabase(NativeDatabase.memory());
    await LegacyImport(db, AppMetaStore(db)).runIfNeeded(legacyPath: legacyPath);

    for (final table in <String>['entry', 'favourites', 'metadata', 'dateTaken', 'covers', 'dynamicAlbums', 'vaults', 'trash', 'videoPlayback', 'debug']) {
      expect(await count(db, table), 1, reason: 'table=$table');
    }
    expect(await status(db), LegacyImportStatus.done);

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

    expect(await status(db), LegacyImportStatus.done);
    expect(await count(db, 'entry'), 0);

    await db.close();
  });

  test('resumes from the last committed chunk after an interruption', () async {
    await seedLegacy(entryCount: 5);

    final db = AppDatabase(NativeDatabase.memory());
    final importer = LegacyImport(db, AppMetaStore(db), chunkSize: 2, staleMs: 0, pollInterval: Duration.zero);

    // Fail after the first committed chunk, as a crash would.
    var calls = 0;
    await expectLater(
      importer.runIfNeeded(
        legacyPath: legacyPath,
        onProgress: (progress) {
          calls++;
          if (calls >= 2) throw StateError('simulated interruption');
        },
      ),
      throwsA(isA<StateError>()),
    );

    final interrupted = await LegacyImportStateStore(AppMetaStore(db)).read();
    expect(interrupted.status, LegacyImportStatus.running);
    expect(interrupted.copiedRows, 2);
    expect(interrupted.totalRows, 14); // 5 entries + one row in each of the 9 other populated tables

    // A new run takes over the stale state and finishes without duplicating.
    await LegacyImport(db, AppMetaStore(db), chunkSize: 2, staleMs: 0, pollInterval: Duration.zero).runIfNeeded(legacyPath: legacyPath);

    expect(await status(db), LegacyImportStatus.done);
    expect(await count(db, 'entry'), 5);
    expect(File(p.join(tempDir.path, LegacyImport.importedBackupFileName)).existsSync(), isTrue);

    await db.close();
  });

  test('a second actor waits while another owns the import', () async {
    await seedLegacy();

    final db = AppDatabase(NativeDatabase.memory());
    final state = LegacyImportStateStore(AppMetaStore(db));

    // Simulate another actor already importing, with a fresh heartbeat.
    await db.transaction(() async {
      await state.takeWriteLock();
      await state.writeClaim(owner: 'other', nowMs: DateTime.now().millisecondsSinceEpoch);
    });

    final seen = <LegacyImportProgress>[];
    final future = LegacyImport(db, AppMetaStore(db), pollInterval: const Duration(milliseconds: 10)).runIfNeeded(
      legacyPath: legacyPath,
      onProgress: seen.add,
    );

    // Let this actor observe the busy state, then finish the other import.
    await Future.delayed(const Duration(milliseconds: 50));
    await db.transaction(() async {
      await state.takeWriteLock();
      await state.writeDone();
    });
    await future;

    // The waiter never imported anything itself.
    expect(await count(db, 'entry'), 0);
    expect(seen, isNotEmpty);
    expect(await status(db), LegacyImportStatus.done);

    await db.close();
  });

  test('reconciles a verification mismatch from a clean slate', () async {
    await seedLegacy(entryCount: 2);

    final db = AppDatabase(NativeDatabase.memory());
    // A stray row makes the drift count differ from the legacy source, which the
    // old code turned into an opaque error on every launch.
    await db.customStatement('INSERT INTO entry(id) VALUES (999)');

    final messages = <String>[];
    Log.setSink((key, level, message, error, stackTrace) => messages.add('$message'));
    Log.setEnabled(LogKeys.db, true);
    try {
      await LegacyImport(db, AppMetaStore(db)).runIfNeeded(legacyPath: legacyPath);
    } finally {
      Log.reset();
    }

    expect(await status(db), LegacyImportStatus.done);
    // The stray row is gone and the legacy rows are intact.
    expect(await count(db, 'entry'), 2);
    expect(
      (await db.customSelect('SELECT id FROM entry ORDER BY id').get()).map((r) => r.data['id']),
      [1, 2],
    );
    // The mismatch is reported with a row-level diff, not just two counts.
    expect(messages.any((m) => m.contains('mismatch') && m.contains('extraIds=[999]')), isTrue);

    await db.close();
  });

  test('progress is monotonic and reaches the total', () async {
    await seedLegacy(entryCount: 5);

    final db = AppDatabase(NativeDatabase.memory());
    final seen = <LegacyImportProgress>[];
    await LegacyImport(db, AppMetaStore(db), chunkSize: 2).runIfNeeded(
      legacyPath: legacyPath,
      onProgress: seen.add,
    );

    final copied = seen.map((p) => p.copiedRows).toList();
    expect(copied, equals(List.of(copied)..sort()), reason: 'progress must never go backwards');
    expect(copied.last, seen.last.totalRows);
    expect(seen.last.totalRows, 14);

    await db.close();
  });
}
