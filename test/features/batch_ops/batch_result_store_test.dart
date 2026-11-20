import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/db/batch_result_store.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late BatchResultStore results;
  late BatchProfileStore profiles;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    results = BatchResultStore(db);
    profiles = BatchProfileStore(db);
  });

  tearDown(() => db.close());

  BatchResult result(String id, {String sourceUri = 'content://media/1', String? resultUri, DateTime? createdAt}) {
    return BatchResult(
      id: id,
      jobId: 'job',
      sourceEntryId: 1,
      sourceUri: sourceUri,
      sourcePath: '/storage/emulated/0/DCIM/1.jpg',
      sourceDirectory: '/storage/emulated/0/DCIM',
      sourceName: '1.jpg',
      resultUri: resultUri ?? 'content://media/$id',
      resultPath: '/storage/emulated/0/Pictures/aves_batch_results/$id.jpg',
      resultFileName: '$id.jpg',
      resultMimeType: 'image/jpeg',
      resultSizeBytes: 10,
      actionsJson: '[]',
      createdAt: createdAt ?? DateTime(2026),
      status: BatchResultStatus.pending,
    );
  }

  group('BatchResultStore', () {
    test('lists results newest first', () async {
      await results.insertResult(result('a', createdAt: DateTime(2026, 1, 1)));
      await results.insertResult(result('b', createdAt: DateTime(2026, 1, 2)));

      final rows = await results.getResults();
      expect([for (final row in rows) row.id], ['b', 'a']);
    });

    test('finds older pending results of one source', () async {
      await results.insertResult(result('a'));
      await results.insertResult(result('b'));
      await results.insertResult(result('other', sourceUri: 'content://media/2'));

      final siblings = await results.getPendingBySource('content://media/1', exceptId: 'b');
      expect([for (final row in siblings) row.id], ['a']);
    });

    test('rewrites where a result lives', () async {
      await results.insertResult(result('a'));
      await results.updateResultLocation(
        'a',
        uri: 'content://media/9',
        path: '/storage/emulated/0/Pictures/aves_batch_results/1.jpg',
        fileName: '1.jpg',
        mimeType: 'image/png',
        sizeBytes: 42,
      );

      final row = (await results.getResults()).single;
      expect(row.resultUri, 'content://media/9');
      expect(row.resultFileName, '1.jpg');
      expect(row.resultMimeType, 'image/png');
      expect(row.resultSizeBytes, 42);
    });

    test('deletes rows by id', () async {
      await results.insertResult(result('a'));
      await results.insertResult(result('b'));

      await results.deleteResults(['a']);
      expect([for (final row in await results.getResults()) row.id], ['b']);
    });
  });

  group('BatchProfileStore', () {
    test('seeds one active default per kind', () async {
      await profiles.ensureSeeded(BatchProfileKind.batch);
      await profiles.ensureSeeded(BatchProfileKind.batch);

      final all = await profiles.getProfiles(BatchProfileKind.batch);
      expect(all, hasLength(1));
      expect(all.single.id, BatchProfileStore.defaultProfileId);
      expect(all.single.isActive, isTrue);
      expect(all.single.name, isEmpty, reason: 'the localized default name lives in the view');
    });

    test('keeps kinds apart', () async {
      await profiles.ensureSeeded(BatchProfileKind.batch);
      await profiles.ensureSeeded(BatchProfileKind.share);

      expect(await profiles.getProfiles(BatchProfileKind.batch), hasLength(1));
      expect(await profiles.getProfiles(BatchProfileKind.share), hasLength(1));
    });

    test('activating one profile deactivates the others', () async {
      await profiles.ensureSeeded(BatchProfileKind.batch);
      final now = DateTime(2026);
      await profiles.saveProfile(
        BatchProfile(
          id: 'second',
          name: 'Second',
          actionsJson: '[]',
          kind: BatchProfileKind.batch,
          sortOrder: 1,
          isActive: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await profiles.setActive(BatchProfileKind.batch, 'second');

      final all = await profiles.getProfiles(BatchProfileKind.batch);
      expect(all.where((profile) => profile.isActive), hasLength(1));
      expect(all.singleWhere((profile) => profile.isActive).id, 'second');
    });

    test('deletes a profile without touching the files', () async {
      await profiles.ensureSeeded(BatchProfileKind.batch);
      await profiles.deleteProfile(BatchProfileStore.defaultProfileId);
      expect(await profiles.getProfiles(BatchProfileKind.batch), isEmpty);
    });
  });
}
