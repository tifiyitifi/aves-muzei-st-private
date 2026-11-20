import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/services/batch_share_service.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Share output is temporary, so retention must read the app's own table, act
/// only on the share folder, and never touch a batch result or a source.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late AppDatabase db;
  late BatchSettings settings;
  late _FakeDb mediaDb;
  late _FakeBatchService native;
  late BatchShareService service;

  final now = DateTime(2026, 6, 10, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    settings = BatchSettings(provider: AppDatabaseProvider(injected: db));
    await settings.ensureLoaded();
    mediaDb = _FakeDb();
    native = _FakeBatchService();
    service = BatchShareService(db: mediaDb, native: native, settings: settings);
  });

  tearDown(() => db.close());

  test('removes only files older than the cutoff', () async {
    final old = _entry(1, service.directory, now.subtract(const Duration(days: 8)));
    final fresh = _entry(2, service.directory, now.subtract(const Duration(days: 1)));
    mediaDb.add([old, fresh]);

    expect(await service.pruneExpired(now: now), 1);

    expect(native.deleted, [old.uri]);
    expect(mediaDb.removed, {old.id});
    expect(mediaDb.queried, [service.directory], reason: 'only the share folder is read');
  });

  test('keeps a file exactly at the cutoff', () async {
    final boundary = _entry(1, service.directory, now.subtract(const Duration(days: BatchSettings.defaultShareRetentionDays)));
    mediaDb.add([boundary]);

    expect(await service.pruneExpired(now: now), 0);

    expect(native.deleted, isEmpty);
    expect(mediaDb.removed, isEmpty);
  });

  test('keeps a file whose modified time is unknown', () async {
    final unknown = _entry(1, service.directory, null);
    mediaDb.add([unknown]);

    expect(await service.pruneExpired(now: now), 0);
    expect(native.deleted, isEmpty);
  });

  test('never removes a batch result or a source', () async {
    final batchResult = _entry(1, '/storage/emulated/0/Pictures/aves_batch_results', now.subtract(const Duration(days: 90)));
    final source = _entry(2, '/storage/emulated/0/DCIM', now.subtract(const Duration(days: 90)));
    mediaDb.add([batchResult, source]);

    expect(await service.pruneExpired(now: now), 0);

    expect(native.deleted, isEmpty);
    expect(mediaDb.removed, isEmpty);
  });

  test('does nothing when retention is off', () async {
    await settings.setShareRetentionDays(0);
    mediaDb.add([_entry(1, service.directory, now.subtract(const Duration(days: 90)))]);

    expect(await service.pruneExpired(now: now), 0);

    expect(native.deleted, isEmpty);
    expect(mediaDb.queried, isEmpty);
  });

  test('a failed delete keeps the row and reports nothing removed', () async {
    native.deleteSucceeds = false;
    mediaDb.add([_entry(1, service.directory, now.subtract(const Duration(days: 8)))]);

    expect(await service.pruneExpired(now: now), 0);

    expect(mediaDb.removed, isEmpty);
  });
}

AvesEntry _entry(int id, String directory, DateTime? modified) {
  final name = 'copy-$id.jpg';
  return AvesEntry(
    id: id,
    uri: 'content://media/$id',
    path: '$directory/$name',
    contentId: id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: '$id',
    dateAddedSecs: 1,
    dateModifiedMillis: modified?.millisecondsSinceEpoch,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );
}

class _FakeDb extends Fake implements LocalMediaDb {
  final Map<String, Set<AvesEntry>> _byDirectory = {};
  final List<String> queried = [];
  final Set<int> removed = {};

  void add(Iterable<AvesEntry> entries) {
    for (final entry in entries) {
      final directory = entry.directory;
      if (directory == null) continue;
      _byDirectory.putIfAbsent(directory, () => {}).add(entry);
    }
  }

  @override
  Future<Set<AvesEntry>> loadEntries({int? origin, String? directory}) async {
    queried.add(directory ?? '');
    return _byDirectory[directory] ?? {};
  }

  @override
  Future<void> removeIds(Set<int> ids, {Set<EntryDataType>? dataTypes}) async {
    removed.addAll(ids);
  }
}

class _FakeBatchService extends Fake implements BatchService {
  final List<String> deleted = [];
  bool deleteSucceeds = true;

  @override
  Stream<BatchEvent> run(BatchJob job) => const Stream.empty();

  @override
  Future<bool> deleteResult(String resultUri) async {
    if (!deleteSucceeds) return false;
    deleted.add(resultUri);
    return true;
  }
}
