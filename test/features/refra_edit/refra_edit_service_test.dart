import 'dart:typed_data';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/refra_edit/db/refra_edit_store.dart';
import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/features/refra_edit/services/refra_edit_service.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/media/enums.dart';
import 'package:aves/services/media/media_edit_service.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

const _staging = '/storage/emulated/0/Pictures/aves_refra_edit';
const _sourceDir = '/storage/emulated/0/DCIM/Camera';
const _stagedUri = 'content://media/external/images/media/100';
const _editedUri = 'content://media/external/images/media/101';
const _copyUri = 'content://media/external/images/media/200';

/// The copy-first edit flow writes to the user's files on the way back.
///
/// Two failures are cheap to introduce and expensive to see: replacing an
/// original with the unedited staged copy, and forgetting where a copy landed.
void main() {
  setUpAll(() async {
    await setUpAllServices();
    ensureSqlite3Loaded();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late AppDatabase db;
  late AppDatabaseProvider provider;
  late DriftLocalMediaDb mediaDb;
  late RefraEditStore store;
  late _FakeMediaEdit mediaEdit;
  late _FakeMediaFetch fetch;
  late RefraEditService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    provider = AppDatabaseProvider(injected: db);
    mediaDb = DriftLocalMediaDb(database: db);
    await mediaDb.init();
    store = RefraEditStore(db);
    mediaEdit = _FakeMediaEdit();
    fetch = _FakeMediaFetch();
    service = RefraEditService(provider: provider, mediaEdit: mediaEdit, fetch: fetch, database: mediaDb);
  });

  tearDown(() async {
    await db.close();
  });

  test('a transfer offers only edited outputs when an unedited copy remains', () {
    final staged = _output('staged', RefraEditOutputKind.staged, uri: _stagedUri, path: '$_staging/1.jpg');
    final edited = _output('edited', RefraEditOutputKind.builtIn, uri: _editedUri, path: '$_staging/1 (1).jpg');

    expect(RefraEditService.transferableOf([staged, edited]).map((o) => o.id), ['s1-edited']);
    // The editor overwrote the staged file in place, so it is the only result.
    expect(RefraEditService.transferableOf([staged]).map((o) => o.id), ['s1-staged']);
  });

  test('moving back leaves the unedited staged copy out of the transfer', () async {
    final session = _session();
    await store.insertSession(session);
    await store.addOutput(_output('staged', RefraEditOutputKind.staged, uri: _stagedUri, path: '$_staging/1.jpg'));
    await store.addOutput(_output('edited', RefraEditOutputKind.builtIn, uri: _editedUri, path: '$_staging/1 (1).jpg'));
    final stagedEntry = _entry(100, _stagedUri, '$_staging/1.jpg');
    final editedEntry = _entry(101, _editedUri, '$_staging/1 (1).jpg');
    await mediaDb.insertEntries({stagedEntry, editedEntry});
    fetch.entries[_stagedUri] = stagedEntry;
    fetch.entries[_editedUri] = editedEntry;

    await service.transferBack(session, copy: false, nameConflictStrategy: NameConflictStrategy.replace);

    expect(mediaEdit.moves, hasLength(1));
    expect(mediaEdit.moves.single.values.single.map((entry) => entry.uri), [_editedUri]);
  });

  test('copying back rewrites where each output lives', () async {
    final session = _session();
    await store.insertSession(session);
    await store.addOutput(_output('staged', RefraEditOutputKind.staged, uri: _stagedUri, path: '$_staging/1.jpg'));
    final stagedEntry = _entry(100, _stagedUri, '$_staging/1.jpg');
    await mediaDb.insertEntries({stagedEntry});
    fetch.entries[_stagedUri] = stagedEntry;
    fetch.entries[_copyUri] = _entry(200, _copyUri, '$_sourceDir/1.jpg');
    mediaEdit.moveEvents.add(
      const MoveOpEvent(
        success: true,
        skipped: false,
        uri: _stagedUri,
        newFields: {'uri': _copyUri, 'path': '$_sourceDir/1.jpg', 'sizeBytes': 20},
        deleted: false,
      ),
    );

    final ok = await service.transferBack(session, copy: true, nameConflictStrategy: NameConflictStrategy.rename);

    expect(ok, isTrue);
    final output = (await store.getOutputs('s1')).single;
    expect(output.uri, _copyUri, reason: 'the record must follow the copy, not the staging file');
    expect(output.path, '$_sourceDir/1.jpg');
    expect(output.sizeBytes, 20);
    expect((await store.getSession('s1'))!.status, RefraEditSessionStatus.copied);
  });

  test('a partial delete commits the files that were removed and keeps the rest', () async {
    final session = _session();
    await store.insertSession(session);
    await store.addOutput(_output('a', RefraEditOutputKind.staged, uri: _stagedUri, path: '$_staging/1.jpg'));
    await store.addOutput(_output('b', RefraEditOutputKind.builtIn, uri: _editedUri, path: '$_staging/2.jpg'));
    final a = _entry(100, _stagedUri, '$_staging/1.jpg');
    final b = _entry(101, _editedUri, '$_staging/2.jpg');
    await mediaDb.insertEntries({a, b});
    fetch.entries[_stagedUri] = a;
    fetch.entries[_editedUri] = b;
    mediaEdit.deleteEvents.addAll([
      const ImageOpEvent(success: true, skipped: false, uri: _stagedUri),
      const ImageOpEvent(success: false, skipped: false, uri: _editedUri),
    ]);

    final records = await service.records();
    final ok = await service.deleteRecords(records.map((item) => item.record));

    expect(ok, isFalse, reason: 'one file could not be deleted');
    // The deleted file lost its row; the one still on disk kept both its row
    // and its output record, so a retry can find it.
    expect((await store.getOutputs('s1')).map((o) => o.uri), [_editedUri]);
    expect((await mediaDb.loadEntriesByUris({_stagedUri, _editedUri})).map((e) => e.uri), [_editedUri]);
  });
}

RefraEditSession _session() => RefraEditSession(
  id: 's1',
  sourceEntryId: 1,
  sourceUri: 'content://media/external/images/media/1',
  sourcePath: '$_sourceDir/1.jpg',
  sourceDirectory: _sourceDir,
  sourceName: '1.jpg',
  sourceMimeType: 'image/jpeg',
  stagingDirectory: _staging,
  stagedUri: _stagedUri,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  status: RefraEditSessionStatus.active,
);

RefraEditOutput _output(String suffix, RefraEditOutputKind kind, {required String uri, required String path}) => RefraEditOutput(
  id: 's1-$suffix',
  sessionId: 's1',
  uri: uri,
  path: path,
  fileName: suffix == 'edited' ? '1 (1).jpg' : '1.jpg',
  kind: kind,
  sizeBytes: 10,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
);

AvesEntry _entry(int id, String uri, String path) => AvesEntry(
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

class _FakeMediaEdit extends Fake implements MediaEditService {
  final List<MoveOpEvent> moveEvents = [];
  final List<ImageOpEvent> deleteEvents = [];
  final List<Map<String, Iterable<AvesEntry>>> moves = [];

  @override
  String get newOpId => 'op';

  @override
  Future<void> cancelFileOp(String opId) async {}

  @override
  Stream<MoveOpEvent> move({
    String? opId,
    required Map<String, Iterable<AvesEntry>> entriesByDestination,
    required bool copy,
    required NameConflictStrategy nameConflictStrategy,
  }) async* {
    moves.add(entriesByDestination);
    for (final event in moveEvents) {
      yield event;
    }
  }

  @override
  Stream<ImageOpEvent> delete({String? opId, required Iterable<AvesEntry> entries}) async* {
    for (final event in deleteEvents) {
      yield event;
    }
  }

  @override
  Stream<ExportOpEvent> export(
    Iterable<AvesEntry> entries, {
    required EntryConvertOptions options,
    required String destinationAlbum,
    required NameConflictStrategy nameConflictStrategy,
  }) => const Stream.empty();

  @override
  Stream<MoveOpEvent> rename({String? opId, required Map<AvesEntry, String> entriesToNewName}) => const Stream.empty();

  @override
  Future<Map<String, Object?>> captureFrame(
    AvesEntry entry, {
    required String desiredName,
    required Map<String, Object> exif,
    required Uint8List bytes,
    required String destinationAlbum,
    required NameConflictStrategy nameConflictStrategy,
  }) async => {};
}

class _FakeMediaFetch extends Fake implements MediaFetchService {
  final Map<String, AvesEntry> entries = {};

  @override
  Future<AvesEntry?> getEntry(String uri, String? mimeType, {bool allowUnsized = false}) async => entries[uri];
}
