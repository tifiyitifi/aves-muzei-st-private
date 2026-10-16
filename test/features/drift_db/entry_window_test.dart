import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Windowed reads (`countEntries` / `loadEntryWindow`) against an in-memory
/// Drift database: total/window consistency, single-level directories,
/// trash exclusion, and the `bestDate` ordering contract.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    // `pContext` (used by the directory predicate) is resolved from GetIt;
    // tests force a POSIX context so path handling matches the app.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDown(() => db.close());

  AvesEntry entry(
    int id, {
    String? dir,
    int dateTaken = 0,
    int size = 5,
    bool trashed = false,
    int origin = EntryOrigins.mediaStoreContent,
  }) {
    final album = dir ?? '/album';
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$album/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: size,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: trashed,
      origin: origin,
    );
  }

  Future<List<int>> windowIds({int limit = 100, int offset = 0, SortFactor sort = SortFactor.date, bool reverse = false, String? directory, bool excludeTrashed = true}) async {
    final window = await service.loadEntryWindow(directory: directory, excludeTrashed: excludeTrashed, sort: sort, reverse: reverse, limit: limit, offset: offset);
    return window.map((e) => e.id).toList();
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  group('countEntries', () {
    test('counts all non-trashed entries by default', () async {
      await service.insertEntries({entry(1), entry(2), entry(3, trashed: true)});
      expect(await service.countEntries(), 2);
      expect(await service.countEntries(excludeTrashed: false), 3);
    });

    test('counts a single directory level only', () async {
      await service.insertEntries({entry(1, dir: '/album'), entry(2, dir: '/album/sub'), entry(3, dir: '/other')});
      expect(await service.countEntries(directory: '/album'), 1);
      expect(await service.countEntries(directory: '/album/sub'), 1);
    });
  });

  group('loadEntryWindow', () {
    test('walks the whole collection without loss or duplication', () async {
      final ids = List.generate(7, (i) => i + 1);
      await service.insertEntries({for (final id in ids) entry(id, dateTaken: id * 10)});
      expect(await service.countEntries(), ids.length);

      final walked = <int>[];
      const limit = 3;
      for (var offset = 0; ; offset += limit) {
        final page = await windowIds(limit: limit, offset: offset);
        if (page.isEmpty) break;
        walked.addAll(page);
      }
      expect(walked, hasLength(ids.length));
      expect(walked.toSet(), ids.toSet());
      // full-range window matches the paged walk
      expect(await windowIds(limit: 100), walked);
    });

    test('orders by bestDate descending, then reverses whole-list', () async {
      await service.insertEntries({entry(1, dateTaken: 30), entry(2, dateTaken: 10), entry(3, dateTaken: 20)});
      expect(await windowIds(), [1, 3, 2]);
      expect(await windowIds(reverse: true), [2, 3, 1]);
    });

    test('prefers the catalogued date over source dates', () async {
      await service.insertEntries({entry(1, dateTaken: 100), entry(2, dateTaken: 10)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 2, dateMillis: 1000)});
      final window = await service.loadEntryWindow(sort: SortFactor.date, reverse: false, limit: 10, offset: 0);
      expect(window.map((e) => e.id), [2, 1]);
      expect(window.firstWhere((e) => e.id == 2).bestDate?.millisecondsSinceEpoch, 1000);
    });

    test('orders by size, rating and path', () async {
      await service.insertEntries({entry(1, dateTaken: 1, size: 30), entry(2, dateTaken: 2, size: 10), entry(3, dateTaken: 3, size: 20)});
      expect(await windowIds(sort: SortFactor.size), [1, 3, 2]);
      expect(await windowIds(sort: SortFactor.path), [1, 2, 3]);

      await service.saveCatalogMetadata({CatalogMetadata(id: 2, rating: 5), CatalogMetadata(id: 3, rating: 2)});
      expect(await windowIds(sort: SortFactor.rating), [2, 3, 1]);
    });

    test('clamps degenerate windows', () async {
      await service.insertEntries({entry(1)});
      expect(await windowIds(limit: 0), isEmpty);
      expect(await windowIds(offset: 99), isEmpty);
    });

    test('supports trashed-only windows with restore details', () async {
      await service.insertEntries({entry(1), entry(2, trashed: true)});
      await service.updateTrash(2, TrashDetails(id: 2, path: '/album/2.jpg', dateMillis: 7));
      final window = await service.loadEntryWindow(trashedOnly: true, excludeTrashed: false, sort: SortFactor.date, reverse: false, limit: 10, offset: 0);
      expect(window.map((e) => e.id), [2]);
      expect(window.single.trashDetails, isNotNull);
      expect(await service.countEntries(trashedOnly: true, excludeTrashed: false), 1);
    });

    test('restricts windows to one section', () async {
      await service.insertEntries({
        entry(1, dir: '/a', dateTaken: millis(2024, 1)),
        entry(2, dir: '/b', dateTaken: millis(2024, 3, 5)),
        entry(3, dir: '/b', dateTaken: millis(2024, 3, 6)),
      });
      await service.saveCatalogMetadata({CatalogMetadata(id: 3, rating: 4)});

      final album = await service.loadEntryWindow(directoryEquals: '/b', sort: SortFactor.date, reverse: false, limit: 10, offset: 0);
      expect(album.map((e) => e.id), [3, 2]);

      final month = await service.loadEntryWindow(dateFromMillis: millis(2024, 3, 1), dateToMillis: millis(2024, 4, 1), sort: SortFactor.date, reverse: false, limit: 10, offset: 0);
      expect(month.map((e) => e.id).toSet(), {2, 3});

      final rated = await service.loadEntryWindow(ratingEquals: 4, sort: SortFactor.rating, reverse: false, limit: 10, offset: 0);
      expect(rated.map((e) => e.id), [3]);
    });
  });
}
