import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/entry/sort.dart';
import 'package:aves/model/filters/aspect_ratio.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/coordinate.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/date.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/missing.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/filters/recent.dart';
import 'package:aves/model/filters/type.dart';
import 'package:aves/model/filters/weekday.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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
    bool pathLess = false,
    int dateTaken = 0,
    int size = 5,
    bool trashed = false,
    int origin = EntryOrigins.mediaStoreContent,
    String mime = 'image/jpeg',
    int? modified = 2,
    int dateAdded = 1,
    int width = 10,
    int height = 20,
    int rotation = 0,
  }) {
    final album = dir ?? '/album';
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: pathLess ? null : '$album/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
      width: width,
      height: height,
      sourceRotationDegrees: rotation,
      sizeBytes: size,
      sourceTitle: 'title$id',
      dateAddedSecs: dateAdded,
      dateModifiedMillis: modified,
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

  /// Inserts [entries] and mirrors the persisted metadata back onto the Dart
  /// objects, so the legacy in-memory `filter.test` can be evaluated for exactly
  /// the rows the database holds.
  Future<void> seed(List<AvesEntry> entries, {Set<CatalogMetadata> catalog = const {}, Set<AddressDetails> addresses = const {}}) async {
    await service.insertEntries(entries.toSet());
    if (catalog.isNotEmpty) await service.saveCatalogMetadata(catalog);
    if (addresses.isNotEmpty) await service.saveAddresses(addresses);
    for (final metadata in catalog) {
      // The setter also mirrors `catalogDateMillis`, like `CatalogStore`.
      entries.firstWhere((e) => e.id == metadata.id).catalogMetadata = metadata;
    }
    for (final address in addresses) {
      entries.firstWhere((e) => e.id == address.id).addressDetails = address;
    }
  }

  /// The SQL predicate must select exactly the rows the legacy in-memory filters
  /// select: the contract behind "browsing a huge library looks the same".
  Future<void> expectMatchesInMemory(Set<CollectionFilter> filters, List<AvesEntry> entries) async {
    final predicate = predicateForFilters(filters);
    expect(predicate, isNotNull, reason: 'filters should compile: $filters');
    final selected = (await windowIds(predicate: predicate!)).toSet();
    final expected = entries.where((e) => filters.every((f) => f.test(e))).map((e) => e.id).toSet();
    expect(selected, expected, reason: 'SQL and in-memory disagreed for $filters');
  }

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

    test('a path filter matches the root and its descendants only', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a/b'), entry(3, dir: '/ab'), entry(4, dir: '/c')});
      // `/ab` must not match `/a`, and `/a/b` is a descendant of `/a`.
      expect((await windowIds(predicate: predicateForFilters({PathFilter('/a')})!)).toSet(), {1, 2});
      expect(await windowIds(predicate: predicateForFilters({PathFilter('/a/b')})!), [2]);
      expect(await windowIds(predicate: predicateForFilters({PathFilter('/a').reverse()})), isNotEmpty);
    });

    test('type filters read the metadata flags and the mime', () async {
      final rawMime = MimeTypes.rawImages.first;
      await service.insertEntries({entry(1, mime: 'video/mp4'), entry(2), entry(3, mime: rawMime)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, isSlowMotion: true)});

      expect(await windowIds(predicate: predicateForFilters({TypeFilter.slowMotion})!), [1]);
      expect(await windowIds(predicate: predicateForFilters({TypeFilter.raw})!), [3]);
      // No entry carries the animated flag.
      expect(await windowIds(predicate: predicateForFilters({TypeFilter.animated})!), isEmpty);
      // The complement keeps the rest (a bare NOT would drop the NULL flag row).
      expect((await windowIds(predicate: predicateForFilters({TypeFilter.animated.reverse()})!)).toSet(), {1, 2, 3});
    });

    test('missing date and title include rows without metadata', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, xmpTitle: 'titled', dateMillis: 1700000000000),
        CatalogMetadata(id: 3, xmpSubjects: 'x'),
      });
      // Entry 2 has no metadata row at all: neither date nor title.
      expect((await windowIds(predicate: predicateForFilters({MissingFilter.date})!)).toSet(), {2, 3});
      expect((await windowIds(predicate: predicateForFilters({MissingFilter.title})!)).toSet(), {2, 3});
    });

    test('missing fine address needs a coordinate without a place', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, latitude: 1, longitude: 1),
        CatalogMetadata(id: 2, latitude: 2, longitude: 2),
      });
      await service.saveAddresses({
        const AddressDetails(id: 1, countryName: 'France', adminArea: 'Paris'),
        const AddressDetails(id: 2, countryName: 'FR'),
      });
      // 1 has a place; 2 has only a two-letter country; 3 has no coordinate.
      expect(await windowIds(predicate: predicateForFilters({MissingFilter.fineAddress})!), [2]);
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

  group('reversed filters', () {
    // The core NULL-safety rule: "not this filter" must keep exactly the rows
    // Dart's `!test` keeps, including the rows a NULL column makes unknown to a
    // bare SQL `NOT`.
    test('a reversed album keeps entries without a directory', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b'), entry(3, pathLess: true)});
      final predicate = predicateForFilters({StoredAlbumFilter('/a', null, reversed: true)})!;
      expect((await windowIds(predicate: predicate)).toSet(), {2, 3});
    });

    test('a reversed tag keeps untagged entries', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, xmpSubjects: 'a'),
        CatalogMetadata(id: 2, xmpSubjects: 'b'),
      });
      final predicate = predicateForFilters({TagFilter('a', reversed: true)})!;
      expect((await windowIds(predicate: predicate)).toSet(), {2, 3});
    });

    test('a reversed mime keeps other mime types', () async {
      await service.insertEntries({entry(1, mime: 'video/mp4'), entry(2), entry(3, mime: 'image/png')});
      final predicate = predicateForFilters({MimeFilter.video.reverse()})!;
      expect((await windowIds(predicate: predicate)).toSet(), {2, 3});
    });

    test('a reversed rating keeps unrated entries', () async {
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, rating: 5), CatalogMetadata(id: 2, rating: 3)});
      final predicate = predicateForFilters({RatingFilter(5).reverse()})!;
      expect((await windowIds(predicate: predicate)).toSet(), {2, 3});
    });

    test('a reversed location keeps entries without an address', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveAddresses({const AddressDetails(id: 1, countryCode: 'FR', countryName: 'France')});
      final predicate = predicateForFilters({LocationFilter(LocationLevel.country, 'France;FR', reversed: true)})!;
      expect(await windowIds(predicate: predicate), [2]);
    });

    test('a reversed filter used as a hidden filter hides its complement', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b')});
      // hiding "not in /a" leaves only /a
      final predicate = predicateForFilters({}, hidden: {StoredAlbumFilter('/a', null, reversed: true)})!;
      expect(await windowIds(predicate: predicate), [1]);
    });
  });

  group('date atoms', () {
    // 2024-03-05 is a Tuesday.
    final day = DateTime(2024, 3, 5, 10);

    Future<List<AvesEntry>> dateEntries() async {
      final entries = [
        entry(1, dateTaken: DateTime(2024, 3, 5, 10).millisecondsSinceEpoch),
        entry(2, dateTaken: DateTime(2024, 3, 6, 10).millisecondsSinceEpoch),
        entry(3, dateTaken: DateTime(2023, 3, 5, 10).millisecondsSinceEpoch),
        // No usable date at all: no catalogued, source nor modification date.
        entry(4, modified: null),
      ];
      await seed(entries);
      return entries;
    }

    test('date filters agree with the in-memory test', () async {
      final entries = await dateEntries();
      for (final level in DateLevel.values) {
        final filter = DateFilter(ACalendar.gregorian, level, day);
        await expectMatchesInMemory({filter}, entries);
        await expectMatchesInMemory({filter.reverse()}, entries);
      }
    });

    test('a year-month-day filter selects exactly that day', () async {
      final entries = await dateEntries();
      final filter = DateFilter(ACalendar.gregorian, DateLevel.ymd, day);
      await expectMatchesInMemory({filter}, entries);
      expect(await windowIds(predicate: predicateForFilters({filter})!), [1]);
    });

    test('non-gregorian calendars keep the legacy path', () {
      for (final calendar in [ACalendar.hijriTbla, ACalendar.hijriUmalqura, ACalendar.persian]) {
        expect(predicateForFilters({DateFilter(calendar, DateLevel.ymd, day)}), isNull, reason: '$calendar');
      }
    });

    test('weekday filters agree with the in-memory test', () async {
      final entries = await dateEntries();
      for (final weekday in [1, 7, day.weekday]) {
        final filter = WeekDayFilter(weekday);
        await expectMatchesInMemory({filter}, entries);
        await expectMatchesInMemory({filter.reverse()}, entries);
      }
    });

    test('recently added agrees around the 24h boundary', () async {
      RecentlyAddedFilter.updateNow();
      final now = RecentlyAddedFilter.nowSecs;
      final entries = [
        entry(1, dateAdded: now - 1),
        entry(2, dateAdded: now - 86399),
        entry(3, dateAdded: now - 86400),
        entry(4, dateAdded: now - 100000),
        entry(5, dateAdded: 0),
      ];
      await seed(entries);
      await expectMatchesInMemory({RecentlyAddedFilter.instance}, entries);
      await expectMatchesInMemory({RecentlyAddedFilter.instance.reverse()}, entries);
      expect((await windowIds(predicate: predicateForFilters({RecentlyAddedFilter.instance})!)).toSet(), {1, 2});
    });

    test('orders dates like the legacy in-memory sort, including 0 and -1 fallbacks', () async {
      final entries = [
        entry(1, dateTaken: 5000, modified: 2),
        entry(2, dateTaken: 0, modified: 2),
        entry(3, dateTaken: 0, modified: 3000),
        entry(4, dateTaken: -1, modified: 1000),
        entry(5, dateTaken: 0, modified: null),
      ];
      // A catalogued date outranks the source date.
      await seed(entries, catalog: {CatalogMetadata(id: 2, dateMillis: 9000)});

      // `sourceDateTakenMillis` 0/-1 are "unknown", so those entries sort by
      // their modification date instead of as if they were from 1970.
      final memoryOrder = (List.of(entries)..sort(AvesEntrySort.compareByDate)).map((e) => e.id).toList();
      expect(memoryOrder, [2, 1, 3, 4, 5]);
      expect(await windowIds(sort: SortFactor.date), memoryOrder);
      expect(await windowIds(sort: SortFactor.date, reverse: true), memoryOrder.reversed);
    });
  });

  group('geometry atoms', () {
    test('aspect ratio filters agree with the in-memory test', () async {
      final entries = [
        entry(1, width: 20, height: 10),
        entry(2, width: 10, height: 20),
        // Rotated: the displayed ratio swaps width and height.
        entry(3, width: 10, height: 20, rotation: 90),
        // Unknown size: the ratio is 1.
        entry(4, width: 0, height: 20),
        // A negative angle: Dart's `%` keeps it in [0, 180) while SQLite's does
        // not, so the compiler adds a second `+ 180`.
        entry(5, width: 10, height: 20, rotation: -90),
      ];
      await seed(entries);

      for (final filter in [
        AspectRatioFilter.landscape,
        AspectRatioFilter.portrait,
        AspectRatioFilter(1, QueryFilter.opEqual),
        AspectRatioFilter.landscape.reverse(),
      ]) {
        await expectMatchesInMemory({filter}, entries);
      }
      // 2, 2 (rotated) and 2 (negative rotation) are landscape.
      expect((await windowIds(predicate: predicateForFilters({AspectRatioFilter.landscape})!)).toSet(), {1, 3, 5});
      expect(await windowIds(predicate: predicateForFilters({AspectRatioFilter.portrait})!), [2]);
    });

    test('coordinate filters agree with the in-memory test', () async {
      final entries = [entry(1), entry(2), entry(3), entry(4)];
      await seed(entries, catalog: {
        CatalogMetadata(id: 1, latitude: 48.85, longitude: 2.35),
        CatalogMetadata(id: 2, latitude: -33.87, longitude: 151.21),
        // The default (0, 0) is not a coordinate.
        CatalogMetadata(id: 3, latitude: 0, longitude: 0),
        CatalogMetadata(id: 4, latitude: 10, longitude: 179),
      });

      final paris = CoordinateFilter(LatLng(48.0, 2.0), LatLng(49.0, 3.0));
      // The west edge is east of the east edge: the box wraps the antimeridian.
      final wrapping = CoordinateFilter(LatLng(-90, 170), LatLng(90, -170));
      for (final filter in [paris, wrapping, paris.reverse()]) {
        await expectMatchesInMemory({filter}, entries);
      }
      expect(await windowIds(predicate: predicateForFilters({paris})!), [1]);
      expect(await windowIds(predicate: predicateForFilters({wrapping})!), [4]);
    });
  });
}
