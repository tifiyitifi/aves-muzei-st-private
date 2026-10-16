import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/metadata/address.dart';
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
    String mime = 'image/jpeg',
  }) {
    final album = dir ?? '/album';
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$album/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
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

  CollectionWindowPredicate lsAlbum(String directory) => predicateForFilters({StoredAlbumFilter(directory, null)})!;

  CollectionWindowPredicate lsTrash() => const CollectionWindowPredicate(trashedOnly: true);

  Future<List<int>> windowIds({int limit = 100, int offset = 0, SortFactor sort = SortFactor.date, bool reverse = false, CollectionWindowPredicate? predicate}) async {
    final window = await service.loadEntryWindow(predicate: predicate ?? const CollectionWindowPredicate(), sort: sort, reverse: reverse, limit: limit, offset: offset);
    return window.map((e) => e.id).toList();
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  group('countEntries', () {
    test('counts all non-trashed entries by default', () async {
      await service.insertEntries({entry(1), entry(2), entry(3, trashed: true)});
      expect(await service.countEntries(), 2);
      expect(await service.countEntries(lsTrash()), 1);
    });

    test('counts a single directory level only', () async {
      await service.insertEntries({entry(1, dir: '/album'), entry(2, dir: '/album/sub'), entry(3, dir: '/other')});
      expect(await service.countEntries(lsAlbum('/album')), 1);
      expect(await service.countEntries(lsAlbum('/album/sub')), 1);
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
      await service.updateTrash(2, const TrashDetails(id: 2, path: '/album/2.jpg', dateMillis: 7));
      final window = await service.loadEntryWindow(predicate: lsTrash(), sort: SortFactor.date, reverse: false, limit: 10, offset: 0);
      expect(window.map((e) => e.id), [2]);
      expect(window.single.trashDetails, isNotNull);
      expect(await service.countEntries(lsTrash()), 1);
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

  group('compiled filter predicates', () {
    test('an album group selects its members', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b'), entry(3, dir: '/c')});
      final group = AlbumGroupFilter(
        Uri.parse('/group'),
        SetOrFilter({StoredAlbumFilter('/a', null), StoredAlbumFilter('/c', null)}),
      );
      expect((await windowIds(predicate: predicateForFilters({group}))).toSet(), {1, 3});
    });

    test('tags select tagged entries; the empty tag selects untagged', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, xmpSubjects: 'sunset;beach'),
        CatalogMetadata(id: 2, xmpSubjects: 'beach'),
        CatalogMetadata(id: 3, xmpSubjects: ''),
      });
      expect(await windowIds(predicate: predicateForFilters({TagFilter('sunset')})), [1]);
      expect((await windowIds(predicate: predicateForFilters({TagFilter('beach')}))).toSet(), {1, 2});
      expect(await windowIds(predicate: predicateForFilters({TagFilter('')})), [3]);
    });

    test('a tag group is the union of its tags', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, xmpSubjects: 'sunset'),
        CatalogMetadata(id: 2, xmpSubjects: 'beach'),
      });
      final group = TagGroupFilter(Uri.parse('/taggroup'), SetOrFilter({TagFilter('sunset'), TagFilter('beach')}));
      expect((await windowIds(predicate: predicateForFilters({group}))).toSet(), {1, 2});
    });

    test('a dynamic album unwraps to its inner filter', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 2, xmpSubjects: 'beach')});
      final album = DynamicAlbumFilter('faves', TagFilter('beach'));
      expect(await windowIds(predicate: predicateForFilters({album})), [2]);
    });

    test('mime and rating filters read metadata', () async {
      await service.insertEntries({entry(1), entry(2, mime: 'video/mp4'), entry(3)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 3, rating: 5)});
      expect(await windowIds(predicate: predicateForFilters({MimeFilter.video})), [2]);
      expect(await windowIds(predicate: predicateForFilters({RatingFilter(5)})), [3]);
    });

    test('a location filter reads the address', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveAddresses({const AddressDetails(id: 1, countryCode: 'FR', countryName: 'France', adminArea: 'Île-de-France', locality: 'Paris')});
      expect(await windowIds(predicate: predicateForFilters({LocationFilter(LocationLevel.country, 'France;FR')})), [1]);
      expect(await windowIds(predicate: predicateForFilters({LocationFilter(LocationLevel.place, 'Paris')})), [1]);
    });

    test('hidden filters are excluded from the window', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/hidden')});
      final predicate = predicateForFilters({}, hidden: {StoredAlbumFilter('/hidden', null)})!;
      expect(await windowIds(predicate: predicate), [1]);
    });

    test('filters intersect (AND)', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a'), entry(3, dir: '/b')});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'beach'), CatalogMetadata(id: 2, xmpSubjects: 'sunset'), CatalogMetadata(id: 3, xmpSubjects: 'beach')});
      final predicate = predicateForFilters({StoredAlbumFilter('/a', null), TagFilter('beach')})!;
      expect(await windowIds(predicate: predicate), [1]);
    });
  });

  group('countEntriesBefore', () {
    // The index must equal the position in the very list loadWindow walks, for
    // every sort factor and both directions: it is what a viewer opens on.
    for (final sort in [SortFactor.date, SortFactor.path, SortFactor.size, SortFactor.rating, SortFactor.duration, SortFactor.albumItemName]) {
      for (final reverse in [false, true]) {
        test('matches the window order for $sort (reverse=$reverse)', () async {
          await service.insertEntries({
            entry(1, dir: '/a', dateTaken: 30, size: 10),
            entry(2, dir: '/b', dateTaken: 10, size: 30),
            entry(3, dir: '/a', dateTaken: 20, size: 20),
            entry(4, dir: '/b', dateTaken: 40, size: 5),
          });
          await service.saveCatalogMetadata({
            CatalogMetadata(id: 1, rating: 5),
            CatalogMetadata(id: 2, rating: 2),
            CatalogMetadata(id: 3, rating: 2),
          });
          final predicate = const CollectionWindowPredicate();
          final ordered = await windowIds(predicate: predicate, sort: sort, reverse: reverse);

          for (var index = 0; index < ordered.length; index++) {
            expect(await service.countEntriesBefore(predicate: predicate, id: ordered[index], sort: sort, reverse: reverse), index, reason: 'sort=$sort reverse=$reverse id=${ordered[index]}');
          }
        });
      }
    }

    test('respects the predicate and reports absent entries as -1', () async {
      await service.insertEntries({entry(1, dir: '/a', dateTaken: 10), entry(2, dir: '/b', dateTaken: 20), entry(3, dir: '/b', dateTaken: 30)});
      final album = lsAlbum('/b');
      // within /b the order is 3, 2
      expect(await service.countEntriesBefore(predicate: album, id: 3, sort: SortFactor.date, reverse: false), 0);
      expect(await service.countEntriesBefore(predicate: album, id: 2, sort: SortFactor.date, reverse: false), 1);
      // entry 1 is not part of the album view
      expect(await service.countEntriesBefore(predicate: album, id: 1, sort: SortFactor.date, reverse: false), -1);
      // unknown ids are absent
      expect(await service.countEntriesBefore(predicate: album, id: 999, sort: SortFactor.date, reverse: false), -1);
    });
  });
}
