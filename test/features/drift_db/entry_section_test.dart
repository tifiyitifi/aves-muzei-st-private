import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Section headers (`loadSectionHeaders`) against an in-memory Drift database:
/// album/month/day/rating grouping, counts, ordering, and predicate scoping.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    // `pContext` (used by the directory column) is resolved from GetIt;
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
    bool trashed = false,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: dir == null ? null : '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  group('loadSectionHeaders', () {
    test('groups albums with counts in path order', () async {
      await service.insertEntries({entry(1, dir: '/b'), entry(2, dir: '/a'), entry(3, dir: '/a'), entry(4, dir: '/a', trashed: true)});
      final headers = await service.loadSectionHeaders(grouping: SectionGrouping.album, reverse: false);
      expect(headers.map((h) => (h.directory, h.count)).toList(), [('/a', 2), ('/b', 1)]);
      expect(await service.loadSectionHeaders(grouping: SectionGrouping.album, reverse: true), headers.reversed.toList());
    });

    test('scopes album headers to a directory', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a/sub'), entry(3, dir: '/b')});
      final headers = await service.loadSectionHeaders(predicate: predicateForFilters({StoredAlbumFilter('/a', null)})!, grouping: SectionGrouping.album, reverse: false);
      // album atom resolves to the maintained directory, so only direct children of /a
      expect(headers.map((h) => h.directory).toList(), ['/a']);
    });

    test('groups Gregorian months and days', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, dateMillis: millis(2024, 1)), CatalogMetadata(id: 2, dateMillis: millis(2024, 1)), CatalogMetadata(id: 3, dateMillis: millis(2024, 3, 5))});

      final months = await service.loadSectionHeaders(grouping: SectionGrouping.month, reverse: false);
      expect(months.map((h) => (h.year, h.month, h.count)).toList(), [(2024, 3, 1), (2024, 1, 2)]);

      final days = await service.loadSectionHeaders(grouping: SectionGrouping.day, reverse: false);
      expect(days.map((h) => (h.year, h.month, h.day, h.count)).toList(), [(2024, 3, 5, 1), (2024, 1, 15, 2)]);
    });

    test('groups ratings with unrated defaulting to zero', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, rating: 5), CatalogMetadata(id: 3, rating: 2)});
      final headers = await service.loadSectionHeaders(grouping: SectionGrouping.rating, reverse: false);
      expect(headers.map((h) => (h.rating, h.count)).toList(), [(5, 1), (2, 1), (0, 1)]);
    });

    test('single returns the window total as one header', () async {
      await service.insertEntries({entry(1), entry(2, trashed: true)});
      final headers = await service.loadSectionHeaders(grouping: SectionGrouping.single, reverse: false);
      expect(headers, [SectionHeader.single(count: 1)]);
      expect(await service.countEntries(), 1);
    });
  });
}
