import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/entries/entry_id_allocator.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  EntryIdAllocator allocator(AppDatabase db, {int blockSize = EntryIdAllocator.defaultBlockSize}) =>
      EntryIdAllocator(db, EntryStore(db), AppMetaStore(db), blockSize: blockSize);

  test('allocators sharing one connection reserve disjoint blocks', () async {
    final a = allocator(db);
    final b = allocator(db);
    await a.init();
    await b.init();

    final idsA = <int>{for (var i = 0; i < 32; i++) a.next()};
    final idsB = <int>{for (var i = 0; i < 32; i++) b.next()};
    expect(idsA, hasLength(32));
    expect(idsB, hasLength(32));
    expect(idsA.intersection(idsB), isEmpty);
  });

  test('allocators on separate connections to one file reserve disjoint blocks', () async {
    // Two connections to one file is what two isolates actually look like, so
    // this exercises the persisted high-water mark, not just in-memory state.
    final dir = await Directory.systemTemp.createTemp('aves_entry_ids');
    final path = p.join(dir.path, 'aves.drift.db');
    // Two AppDatabase *instances* over *distinct* executors is intentional here
    // (it models two isolates); silence drift's same-executor warning.
    final warn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dbA = AppDatabase(NativeDatabase(File(path)));
    final dbB = AppDatabase(NativeDatabase(File(path)));
    try {
      final a = allocator(dbA);
      final b = allocator(dbB);
      await a.init();
      await b.init();

      final ids = <int>{for (var i = 0; i < 16; i++) a.next(), for (var i = 0; i < 16; i++) b.next()};
      expect(ids, hasLength(32));
    } finally {
      await dbA.close();
      await dbB.close();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = warn;
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('rolls over to a fresh block without reusing an id', () async {
    final a = allocator(db, blockSize: 4);
    await a.init();

    final ids = <int>[];
    for (var i = 0; i < 12; i++) {
      ids.add(a.next());
      await a.settled;
    }
    expect(ids, hasLength(12));
    expect(ids.toSet(), hasLength(12));
    expect(ids, orderedEquals([...ids]..sort()));
  });

  test('seeds the first block above the existing entries', () async {
    // A database that predates this allocator has entries but no high-water
    // mark, so a fresh allocator must not hand out an id at or below the max.
    await db.into(db.entriesTable).insert(const EntriesTableCompanion(id: Value(5000)));
    final a = allocator(db);
    await a.init();
    expect(a.next(), greaterThan(5000));
  });
}
