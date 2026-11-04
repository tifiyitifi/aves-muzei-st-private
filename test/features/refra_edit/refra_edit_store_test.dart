import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/refra_edit/db/refra_edit_store.dart';
import 'package:aves/features/refra_edit/model/refra_edit_paths.dart';
import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// The copy-first edit tables and the store that owns them.
///
/// A session must keep its source directory even after the copies are gone, and its outputs must
/// be countable per session: that count is the "how many results did this edit produce" answer.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late RefraEditStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = RefraEditStore(db);
  });

  tearDown(() => db.close());

  RefraEditSession session(String id) => RefraEditSession(
    id: id,
    sourceEntryId: 42,
    sourceUri: 'content://media/external/images/media/42',
    sourcePath: '/storage/emulated/0/DCIM/Camera/IMG_1.jpg',
    sourceDirectory: '/storage/emulated/0/DCIM/Camera',
    sourceName: 'IMG_1.jpg',
    sourceMimeType: 'image/jpeg',
    stagingDirectory: '/storage/emulated/0/Pictures/aves_refra_edit/$id',
    stagedUri: 'content://media/external/images/media/100',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    status: RefraEditSessionStatus.active,
  );

  RefraEditOutput output(String sessionId, int index) => RefraEditOutput(
    id: '$sessionId-$index',
    sessionId: sessionId,
    uri: 'content://media/external/images/media/${100 + index}',
    path: '/storage/emulated/0/Pictures/aves_refra_edit/$sessionId/$index.jpg',
    fileName: '$index.jpg',
    kind: index == 0 ? RefraEditOutputKind.staged : RefraEditOutputKind.builtIn,
    sizeBytes: 10,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000 + index),
  );

  test('a session round-trips with its source directory intact', () async {
    await store.insertSession(session('s1'));

    final loaded = await store.getSession('s1');
    expect(loaded, isNotNull);
    expect(loaded!.sourceDirectory, '/storage/emulated/0/DCIM/Camera');
    expect(loaded.sourceName, 'IMG_1.jpg');
    expect(loaded.status, RefraEditSessionStatus.active);
  });

  test('outputs are counted per session', () async {
    await store.insertSession(session('s1'));
    await store.insertSession(session('s2'));
    await store.addOutput(output('s1', 0));
    await store.addOutput(output('s1', 1));
    await store.addOutput(output('s1', 2));
    await store.addOutput(output('s2', 0));

    final counts = await store.watchOutputCounts().first;
    expect(counts['s1'], 3);
    expect(counts['s2'], 1);

    final outputs = await store.getOutputs('s1');
    expect(outputs.map((o) => o.fileName), ['0.jpg', '1.jpg', '2.jpg']);
    expect(outputs.first.kind, RefraEditOutputKind.staged);
    expect(outputs.last.kind, RefraEditOutputKind.builtIn);
  });

  test('moving back marks the session and keeps its history', () async {
    await store.insertSession(session('s1'));
    await store.setSessionStatus('s1', RefraEditSessionStatus.moved);

    final loaded = await store.getSession('s1');
    expect(loaded!.status, RefraEditSessionStatus.moved);
    expect(await store.getActiveSessions(), isEmpty);
  });

  test('every session stages into the same album folder', () {
    expect(refraEditStagingRelativeRoot, 'Pictures/aves_refra_edit');
  });

  test('the staging tree is recognised however its path is written', () {
    expect(isRefraEditStagingPath('/storage/emulated/0/Pictures/aves_refra_edit'), isTrue);
    expect(isRefraEditStagingPath('/storage/emulated/0/Pictures/aves_refra_edit/1793818801'), isTrue);
    expect(isRefraEditStagingPath(r'D:\phone\Pictures\Aves_Refra_Edit\1793818801'), isTrue);
    // A user album that merely shares the prefix is not the staging tree.
    expect(isRefraEditStagingPath('/storage/emulated/0/Pictures/aves_refra_edit_2'), isFalse);
    expect(isRefraEditStagingPath('/storage/emulated/0/Pictures'), isFalse);
  });
}
