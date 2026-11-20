import 'dart:typed_data';

import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_result_recorder.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/media/enums.dart';
import 'package:aves/services/media/media_edit_service.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

const _sourceUri = 'content://media/1';
const _sourceDir = '/storage/emulated/0/DCIM';
const _resultsDir = '/storage/emulated/0/Pictures/aves_batch_results';

/// Batch results are recorded, superseded and applied without touching storage
/// in the test: the native and media-edit services are faked, the row bookkeeping
/// and the app's entry table are real.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late AppDatabase db;
  late AppDatabaseProvider provider;
  late DriftLocalMediaDb mediaDb;
  late BatchSettings batchSettings;
  late _FakeEntryStore store;
  late _FakeMediaEdit mediaEdit;
  late _FakeBatchService native;
  late BatchResultsService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    provider = AppDatabaseProvider(injected: db);
    mediaDb = DriftLocalMediaDb(database: db);
    await mediaDb.init();
    batchSettings = BatchSettings(provider: provider);
    await batchSettings.ensureLoaded();

    store = _FakeEntryStore();
    mediaEdit = _FakeMediaEdit(store);
    native = _FakeBatchService();
    service = BatchResultsService(
      provider: provider,
      native: native,
      mediaEdit: mediaEdit,
      db: mediaDb,
      fetch: _FakeMediaFetch(store),
      batchSettingsOverride: batchSettings,
    );

    final source = _entry(1, _sourceUri, '$_sourceDir/1.jpg');
    await mediaDb.insertEntries({source});
    store.entries[source.uri] = source;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> record({
    String resultUri = 'content://media/200',
    String resultPath = '$_resultsDir/1.jpg',
    String resultName = '1.jpg',
    String output = batchResultsRelativeRoot,
    int index = 0,
    String jobId = 'job',
  }) async {
    await service.record(
      BatchRecordedItem(
        jobId: jobId,
        index: index,
        item: const BatchItem(entryId: 1, uri: _sourceUri, displayName: '1.jpg', mimeType: 'image/jpeg'),
        actions: [BatchActions.rotate()],
        resultUri: resultUri,
        resultPath: resultPath,
        resultName: resultName,
        resultSize: 100,
        resultMimeType: 'image/jpeg',
        outputRelativePath: output,
      ),
    );
  }

  test('records a result with its source and the actions that produced it', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();

    final rows = await (await service.store()).getResults();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.sourceUri, _sourceUri);
    expect(row.sourceDirectory, _sourceDir);
    expect(row.resultUri, 'content://media/200');
    expect(row.resultPath, '$_resultsDir/1.jpg');
    expect(row.resultFileName, '1.jpg');
    expect(row.resultSizeBytes, 100);
    expect(row.status, BatchResultStatus.pending);
    expect(decodeBatchActions(row.actionsJson).single.kind, BatchToolKind.rotate);
  });

  test('ignores a run that writes outside the results folder', () async {
    await record(output: 'Pictures/aves_share_batch');
    expect(await (await service.store()).getResults(), isEmpty);
  });

  test('ignores a copy & share run', () async {
    await record(
      output: batchShareRelativeRoot,
      resultPath: '/storage/emulated/0/Pictures/aves_share/1_20260101_120000.jpg',
      resultName: '1_20260101_120000.jpg',
    );
    expect(await (await service.store()).getResults(), isEmpty);
  });

  test('replace-previous parks and deletes the older result, then frees its name', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record(resultUri: 'content://media/200', resultName: '1.jpg');

    // The second write collides with the first, so MediaStore named it `1 (1).jpg`.
    store.entries['content://media/201'] = _entry(201, 'content://media/201', '$_resultsDir/1 (1).jpg');
    await record(resultUri: 'content://media/201', resultPath: '$_resultsDir/1 (1).jpg', resultName: '1 (1).jpg', index: 1);

    final rows = await (await service.store()).getResults();
    expect(rows, hasLength(1));
    expect(rows.single.resultFileName, '1.jpg');
    // The rename gave the file a new MediaStore id; the row follows it.
    expect(rows.single.resultUri, startsWith('content://media/9'));

    expect(mediaEdit.renames.map((entry) => entry.value), containsAll(['1-to-remove.jpg', '1.jpg']));
    expect(native.deleted, hasLength(1), reason: 'the parked file is consumed');
  });

  test('keep-versions leaves both results pending', () async {
    await batchSettings.setResultMode(BatchResultMode.keepVersions);
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record(resultUri: 'content://media/200', resultName: '1.jpg');
    store.entries['content://media/201'] = _entry(201, 'content://media/201', '$_resultsDir/1_20260101.jpg');
    await record(resultUri: 'content://media/201', resultName: '1_20260101.jpg', index: 1);

    final rows = await (await service.store()).getResults();
    expect(rows, hasLength(2));
    expect(mediaEdit.renames, isEmpty);
    expect(native.deleted, isEmpty);
  });

  test('replacing a source consumes its result and keeps the row count honest', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();
    final row = (await (await service.store()).getResults()).single;

    final replaced = await service.replaceWithSource([row]);

    expect(replaced, 1);
    expect(native.requestedAccess, [_sourceUri], reason: 'write access is requested before the first write');
    expect(native.replaced.single.key, _sourceUri);
    expect(native.replaced.single.value, 'content://media/200');
    expect(await (await service.store()).getResults(), isEmpty);
  });

  test('a failed replacement keeps the result pending', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();
    final row = (await (await service.store()).getResults()).single;
    native.replaceSucceeds = false;

    expect(await service.replaceWithSource([row]), 0);
    expect(await (await service.store()).getResults(), hasLength(1));
  });

  test('moving back uses the source folder and renames on conflict', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();
    final row = (await (await service.store()).getResults()).single;

    final moved = await service.moveBack([row]);

    expect(moved, 1);
    expect(mediaEdit.moves.single.keys.single, _sourceDir);
    expect(mediaEdit.lastConflict, NameConflictStrategy.rename);
    expect(await (await service.store()).getResults(), isEmpty);
  });

  test('prunes rows whose result file disappeared', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();
    store.entries.remove('content://media/200');

    expect(await service.pruneMissingResults(), 1);
    expect(await (await service.store()).getResults(), isEmpty);
  });

  test('asks the platform before pruning a fresh result', () async {
    // Written seconds ago, so the scanner has not indexed it yet: the app's
    // table cannot answer, and the platform must be asked before the row is
    // treated as missing.
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record();

    expect(await service.pruneMissingResults(), 0);
    expect(await (await service.store()).getResults(), hasLength(1));
  });

  test('leaves both files when the superseded result cannot be deleted', () async {
    store.entries['content://media/200'] = _entry(200, 'content://media/200', '$_resultsDir/1.jpg');
    await record(resultUri: 'content://media/200', resultName: '1.jpg');

    native.deleteSucceeds = false;
    store.entries['content://media/201'] = _entry(201, 'content://media/201', '$_resultsDir/1 (1).jpg');
    await record(resultUri: 'content://media/201', resultPath: '$_resultsDir/1 (1).jpg', resultName: '1 (1).jpg', index: 1);

    // The parked copy survived, so the newer result still took the plain name.
    // Both files and both rows stay: a half-finished cleanup loses nothing.
    final paths = store.entries.values.map((entry) => entry.path).toList(growable: false);
    expect(paths, containsAll(['$_resultsDir/1-to-remove.jpg', '$_resultsDir/1.jpg']));
    final rows = await (await service.store()).getResults();
    expect(rows, hasLength(2));
    expect(native.deleted, hasLength(1), reason: 'the delete was attempted, not skipped');
  });

  test('deletes parked files left by an interrupted cleanup', () async {
    final parked = _entry(300, 'content://media/300', '$_resultsDir/1-to-remove.jpg');
    final result = _entry(301, 'content://media/301', '$_resultsDir/2.jpg');
    await mediaDb.insertEntries({parked, result});

    expect(await service.pruneSupersededFiles(), 1);

    expect(native.deleted, [parked.uri]);
    final remaining = await mediaDb.loadEntries(directory: service.resultsDirectory);
    expect(remaining.map((entry) => entry.path), [result.path]);
  });
}

AvesEntry _entry(int id, String uri, String path) {
  return AvesEntry(
    id: id,
    uri: uri,
    path: path,
    contentId: id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: '$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );
}

class _FakeEntryStore {
  final Map<String, AvesEntry> entries = {};
  int _nextId = 900;

  String nextUri() => 'content://media/${_nextId++}';
}

class _FakeMediaFetch extends Fake implements MediaFetchService {
  final _FakeEntryStore store;

  new(this.store);

  @override
  Future<AvesEntry?> getEntry(String uri, String? mimeType, {bool allowUnsized = false}) async => store.entries[uri];
}

class _FakeMediaEdit extends Fake implements MediaEditService {
  final _FakeEntryStore store;

  new(this.store);

  final List<MapEntry<AvesEntry, String>> renames = [];
  final List<Map<String, Iterable<AvesEntry>>> moves = [];
  NameConflictStrategy? lastConflict;

  @override
  String get newOpId => 'op';

  @override
  Future<void> cancelFileOp(String opId) async {}

  @override
  Stream<ImageOpEvent> delete({String? opId, required Iterable<AvesEntry> entries}) => const Stream.empty();

  @override
  Stream<ExportOpEvent> export(
    Iterable<AvesEntry> entries, {
    required EntryConvertOptions options,
    required String destinationAlbum,
    required NameConflictStrategy nameConflictStrategy,
  }) => const Stream.empty();

  @override
  Future<Map<String, Object?>> captureFrame(
    AvesEntry entry, {
    required String desiredName,
    required Map<String, Object> exif,
    required Uint8List bytes,
    required String destinationAlbum,
    required NameConflictStrategy nameConflictStrategy,
  }) async => {};

  @override
  Stream<MoveOpEvent> rename({String? opId, required Map<AvesEntry, String> entriesToNewName}) async* {
    for (final entry in entriesToNewName.entries) {
      renames.add(MapEntry(entry.key, entry.value));
      final newUri = store.nextUri();
      final directory = entry.key.directory ?? _resultsDir;
      final renamed = entry.key.copyWith(uri: newUri, path: '$directory/${entry.value}');
      store.entries.remove(entry.key.uri);
      store.entries[newUri] = renamed;
      yield MoveOpEvent(
        success: true,
        skipped: false,
        uri: entry.key.uri,
        newFields: {'uri': newUri, 'path': renamed.path},
        deleted: false,
      );
    }
  }

  @override
  Stream<MoveOpEvent> move({
    String? opId,
    required Map<String, Iterable<AvesEntry>> entriesByDestination,
    required bool copy,
    required NameConflictStrategy nameConflictStrategy,
  }) async* {
    moves.add(entriesByDestination);
    lastConflict = nameConflictStrategy;
    for (final destination in entriesByDestination.entries) {
      for (final entry in destination.value) {
        final newUri = store.nextUri();
        final name = (entry.path ?? entry.uri).split('/').last;
        final moved = entry.copyWith(uri: newUri, path: '${destination.key}/$name');
        store.entries.remove(entry.uri);
        store.entries[newUri] = moved;
        yield MoveOpEvent(
          success: true,
          skipped: false,
          uri: entry.uri,
          newFields: {'uri': newUri, 'path': moved.path},
          deleted: false,
        );
      }
    }
  }
}

class _FakeBatchService extends Fake implements BatchService {
  final List<MapEntry<String, String>> replaced = [];
  final List<String> deleted = [];
  final List<String> requestedAccess = [];
  bool replaceSucceeds = true;
  bool deleteSucceeds = true;

  @override
  Stream<BatchEvent> run(BatchJob job) => const Stream.empty();

  @override
  Future<void> cancel(String jobId) async {}

  @override
  Future<bool> replaceWithResult({required String sourceUri, required String resultUri}) async {
    replaced.add(MapEntry(sourceUri, resultUri));
    return replaceSucceeds;
  }

  @override
  Future<bool> deleteResult(String resultUri) async {
    deleted.add(resultUri);
    return deleteSucceeds;
  }

  @override
  Future<bool> requestWriteAccess({required List<String> uris, required List<String> mimeTypes}) async {
    requestedAccess.addAll(uris);
    return true;
  }
}
