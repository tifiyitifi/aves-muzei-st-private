import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/drift_db/filter_summary/filter_summary_store.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// DB-backed filter summaries (`album/tag/locationRows`) against an in-memory
/// Drift database: grouping, aggregates, `bestDate` parity with `loadWindow`,
/// trash exclusion, and hidden-filter exclusion.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;
  late FilterSummaryStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
    store = FilterSummaryStore(db);
  });

  tearDown(() => db.close());

  AvesEntry entry(
    int id, {
    String? dir,
    int size = 5,
    bool trashed = false,
    int sourceDateTaken = 0,
    int modified = 2,
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
      dateModifiedMillis: modified,
      sourceDateTakenMillis: sourceDateTaken,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  CatalogMetadata metadata(
    int id, {
    String? subjects,
    int dateMillis = 0,
    double? latitude,
    double? longitude,
  }) =>
      CatalogMetadata(
        id: id,
        dateMillis: dateMillis,
        xmpSubjects: subjects,
        latitude: latitude,
        longitude: longitude,
      );

  AddressDetails address(
    int id, {
    String? countryCode,
    String? countryName,
    String? adminArea,
    String? locality,
  }) =>
      AddressDetails(
        id: id,
        countryCode: countryCode,
        countryName: countryName,
        adminArea: adminArea,
        locality: locality,
      );

  SummaryExclusion noExclusion() => buildSummaryExclusion(hidden: {}, lockedVaultDirs: {});

  group('albumRows', () {
    test('groups by directory with count, size and best date', () async {
      await service.insertEntries({entry(1, dir: '/a', size: 10, sourceDateTaken: 100), entry(2, dir: '/a', size: 20, sourceDateTaken: 300), entry(3, dir: '/b', size: 40, sourceDateTaken: 200)});
      await service.saveCatalogMetadata({metadata(2, dateMillis: 50)});

      final rows = await store.albumRows(noExclusion());
      expect(rows.map((r) => r.directory), ['/a', '/b']);
      final a = rows.firstWhere((r) => r.directory == '/a');
      expect(a.count, 2);
      expect(a.sizeBytes, 30);
      // `bestDate` is COALESCE-first, not max-first: the catalogued date (50)
      // wins over the larger source date (300) for entry 2, so entry 1 (100)
      // is both the max and the most recent.
      expect(a.maxBestDate, 100);
      expect(a.recentId, 1);
      final b = rows.firstWhere((r) => r.directory == '/b');
      expect((b.count, b.sizeBytes, b.maxBestDate, b.recentId), (1, 40, 200, 3));
    });

    test('catalogued date wins best date when largest', () async {
      await service.insertEntries({entry(1, sourceDateTaken: 100)});
      await service.saveCatalogMetadata({metadata(1, dateMillis: 500)});

      final rows = await store.albumRows(noExclusion());
      expect(rows.single.maxBestDate, 500);
      expect(rows.single.recentId, 1);
    });

    test('excludes trashed entries', () async {
      await service.insertEntries({entry(1), entry(2, trashed: true)});
      final rows = await store.albumRows(noExclusion());
      expect(rows.single.count, 1);
    });

    test('excludes hidden albums and locked vaults', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/secret'), entry(3, dir: '/hidden')});
      final exclusion = buildSummaryExclusion(hidden: {StoredAlbumFilter('/hidden', null)}, lockedVaultDirs: {'/secret'});
      final rows = await store.albumRows(exclusion);
      expect(rows.map((r) => r.directory), ['/a']);
    });

    test('returns empty list on empty database', () async {
      expect(await store.albumRows(noExclusion()), isEmpty);
    });
  });

  group('tagRows', () {
    test('splits multi-tag subjects and aggregates per tag', () async {
      await service.insertEntries({entry(1, size: 10, sourceDateTaken: 100), entry(2, size: 20, sourceDateTaken: 300), entry(3, size: 40, sourceDateTaken: 200)});
      await service.saveCatalogMetadata({metadata(1, subjects: 'red;blue'), metadata(2, subjects: 'blue'), metadata(3)});

      final rows = await store.tagRows(noExclusion());
      expect(rows.map((r) => r.tag), ['blue', 'red']);
      final blue = rows.firstWhere((r) => r.tag == 'blue');
      expect((blue.count, blue.sizeBytes, blue.maxBestDate, blue.recentId), (2, 30, 300, 2));
      final red = rows.firstWhere((r) => r.tag == 'red');
      expect((red.count, red.sizeBytes), (1, 10));
    });

    test('excludes hidden tags without substring leakage', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveCatalogMetadata({metadata(1, subjects: 'ab'), metadata(2, subjects: 'a')});
      final exclusion = buildSummaryExclusion(hidden: {TagFilter('a')}, lockedVaultDirs: {});
      final rows = await store.tagRows(exclusion);
      expect(rows.map((r) => r.tag), ['ab']);
    });

    test('excludes untagged entries when untagged is hidden', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveCatalogMetadata({metadata(1, subjects: 'x'), metadata(2)});
      final exclusion = buildSummaryExclusion(hidden: {TagFilter('')}, lockedVaultDirs: {});
      final rows = await store.tagRows(exclusion);
      expect(rows.map((r) => r.tag), ['x']);
    });
  });

  group('locationRows', () {
    test('groups countries, states and places', () async {
      await service.insertEntries({entry(1, sourceDateTaken: 100), entry(2, sourceDateTaken: 300), entry(3, sourceDateTaken: 200)});
      await service.saveCatalogMetadata({metadata(1, latitude: 1, longitude: 1), metadata(2, latitude: 2, longitude: 2), metadata(3, latitude: 3, longitude: 3)});
      await service.saveAddresses({
        address(1, countryCode: 'FR', countryName: 'France', adminArea: 'Paris', locality: 'Paris'),
        address(2, countryCode: 'FR', countryName: 'France', adminArea: 'Lyon', locality: ''),
        address(3, countryCode: 'US', countryName: 'United States', adminArea: 'California', locality: 'SF'),
      });

      final countries = await store.countryRows(noExclusion());
      expect(countries.map((r) => r.code), ['FR', 'US']);
      expect(countries.firstWhere((r) => r.code == 'FR').count, 2);

      final places = await store.placeRows(noExclusion());
      // empty locality falls back to adminArea
      expect(places.map((r) => r.place).toSet(), {'Paris', 'Lyon', 'SF'});
      final paris = places.firstWhere((r) => r.place == 'Paris');
      expect((paris.count, paris.recentId), (1, 1));
    });

    test('excludes hidden locations', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveCatalogMetadata({metadata(1, latitude: 1, longitude: 1), metadata(2, latitude: 2, longitude: 2)});
      await service.saveAddresses({
        address(1, countryCode: 'FR', countryName: 'France', adminArea: 'Paris', locality: 'Paris'),
        address(2, countryCode: 'US', countryName: 'United States', adminArea: 'California', locality: 'SF'),
      });
      final exclusion = buildSummaryExclusion(hidden: {LocationFilter(LocationLevel.country, 'France;FR')}, lockedVaultDirs: {});
      final countries = await store.countryRows(exclusion);
      expect(countries.map((r) => r.code), ['US']);
      final places = await store.placeRows(exclusion);
      expect(places.map((r) => r.place), ['SF']);
    });
  });

  group('buildSummaryExclusion', () {
    test('is empty without hidden filters or vaults', () {
      final exclusion = buildSummaryExclusion(hidden: {}, lockedVaultDirs: {});
      expect(exclusion.isEmpty, true);
      expect(exclusion.complete, isTrue);
    });

    test('hides the complement of a reversed hidden filter', () async {
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/b')});
      // "not in /a" hides entry 2; a bare `NOT` would also drop rows whose
      // directory is NULL, which the Dart test keeps.
      final exclusion = buildSummaryExclusion(hidden: {StoredAlbumFilter('/a', null, reversed: true)}, lockedVaultDirs: {});
      expect(exclusion.complete, isTrue);
      expect((await store.albumRows(exclusion)).map((r) => r.directory), ['/a']);
    });

    test('hiding unlocated entries keeps located ones', () async {
      await service.insertEntries({entry(1), entry(2)});
      await service.saveCatalogMetadata({metadata(1, latitude: 1, longitude: 1)});
      final exclusion = buildSummaryExclusion(hidden: {LocationFilter(LocationLevel.place, '')}, lockedVaultDirs: {});
      expect((await store.albumRows(exclusion)).single.count, 1);
    });

    test('reports an unexpressible hidden filter instead of dropping it', () async {
      final exclusion = buildSummaryExclusion(hidden: {QueryFilter(r'/title/', ACalendar.gregorian)}, lockedVaultDirs: {});
      // The summary stays approximate (the filter is skipped) but flags it, so
      // the window predicate can fall back to the legacy path.
      expect(exclusion.complete, isFalse);
      expect(exclusion.isEmpty, isTrue);
    });
  });
}
