import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/stats/collection_stats.dart';
import 'package:aves/features/collection_paging/stats/paged_stats_source.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/date.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Statistics of a windowed scope: the database walk must fold the same numbers
/// an in-memory collection would, in bounded chunks.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  late AppDatabase db;
  late DriftLocalMediaDb driftDb;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    driftDb = DriftLocalMediaDb(database: db);
    await driftDb.init();
    getIt.unregister<LocalMediaDb>();
    getIt.registerLazySingleton<LocalMediaDb>(() => driftDb);
  });

  tearDownAll(() async {
    await tearDownAllServices();
    await db.close();
  });

  setUp(() async {
    await collectionPagingPrefs.init();
    await collectionPagingPrefs.setEngine(CollectionEngine.auto);
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearAddresses();
    await driftDb.clearTrashDetails();
  });

  tearDown(() async {
    await setUpServices();
  });

  AvesEntry entry(int id, {String dir = '/album', int sizeBytes = 5}) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: '$dir/$id.jpg',
        contentId: 100 + id,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: sizeBytes,
        sourceTitle: 'title$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: DateTime(2024, 1, id).millisecondsSinceEpoch,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  /// Three rows: a catalogued one with tags, rating, GPS and an address, a
  /// catalogued one without any of those, and an uncatalogued one.
  Future<void> seed() async {
    await driftDb.insertEntries({for (var i = 1; i <= 3; i++) entry(i)});
    await driftDb.updateCatalogMetadata(1, CatalogMetadata(id: 1, mimeType: 'image/heic', xmpSubjects: 'sunset;beach;', rating: 4, latitude: 48.85, longitude: 2.35, dateMillis: DateTime(2024, 1, 1).millisecondsSinceEpoch));
    await driftDb.updateCatalogMetadata(2, CatalogMetadata(id: 2, mimeType: 'image/png', rating: 0, dateMillis: DateTime(2024, 1, 2).millisecondsSinceEpoch));
    await driftDb.saveAddresses({const AddressDetails(id: 1, countryName: 'France', countryCode: 'FR', adminArea: 'Ile-de-France', locality: 'Paris')});
  }

  test('the walk folds the same numbers as an in-memory aggregation', () async {
    await seed();
    // Two chunks for three rows, so the walk crosses a chunk boundary.
    const source = PagedStatsSource(predicate: CollectionWindowPredicate(), entryCount: 3, chunkSize: 2);
    final stats = await source.load();

    expect(stats.entryCount, 3);

    // The same rows, aggregated in memory: the walk must agree with it, down to
    // the catalogued dates the `dateTaken` table carries.
    final accumulator = CollectionStatsAccumulator(ACalendar.gregorian);
    for (final item in await driftDb.loadEntriesById({1, 2, 3})) {
      final meta = (await driftDb.loadCatalogMetadataById({item.id})).firstOrNull;
      final address = (await driftDb.loadAddressesById({item.id})).firstOrNull;
      // What the source seeds from `dateTaken`, the walk reads from the row.
      item.catalogDateMillis = meta?.dateMillis;
      item.catalogMetadata = meta;
      item.addressDetails = address;
      accumulator.add((entry: item, metadata: meta, address: address));
    }
    final expected = accumulator.build();

    expect(stats.totalSizeBytes, expected.totalSizeBytes);
    expect(stats.cataloguedCount, expected.cataloguedCount);
    expect(stats.withGpsCount, expected.withGpsCount);
    expect(stats.entryCountPerAlbum, expected.entryCountPerAlbum);
    expect(stats.entryCountPerRating, expected.entryCountPerRating);
    expect(stats.entryCountPerMimeType, expected.entryCountPerMimeType);
    expect(stats.entryCountPerTag, expected.entryCountPerTag);
    expect(stats.entryCountPerCountry, expected.entryCountPerCountry);
    expect(stats.entryCountPerPlace, expected.entryCountPerPlace);
    expect(stats.histogram?.level, expected.histogram?.level);
    expect(stats.histogram?.entryCountPerDate, expected.histogram?.entryCountPerDate);
  });

  test('the aggregate carries the numbers the page shows', () async {
    await seed();
    final stats = await const PagedStatsSource(predicate: CollectionWindowPredicate(), entryCount: 3, chunkSize: 2).load();

    expect(stats.entryCount, 3);
    expect(stats.totalSizeBytes, 15);
    expect(stats.cataloguedCount, 2);
    expect(stats.withGpsCount, 1);
    expect(stats.entryCountPerMimeType, {'image/heic': 1, 'image/png': 1, 'image/jpeg': 1});
    expect(stats.entryCountPerRating, {5: 0, 4: 1, 3: 0, 2: 0, 1: 0, 0: 2});
    expect(stats.entryCountPerAlbum, {'/album': 3});
    expect(stats.entryCountPerTag, {'sunset': 1, 'beach': 1});
    expect(stats.entryCountPerCountry, {'France${LocationFilter.locationSeparator}FR': 1});
    expect(stats.entryCountPerPlace, {'Paris': 1});
    // The catalogued dates span two days, so the chart buckets by day: the
    // uncatalogued row falls back to its own source date.
    expect(stats.histogram?.level, DateLevel.ymd);
    expect(stats.histogram?.entryCountPerDate, {
      DateTime(2024, 1, 1): 1,
      DateTime(2024, 1, 2): 1,
      DateTime(2024, 1, 3): 1,
    });
  });

  test('the scope is the predicate, not the whole library', () async {
    await seed();
    await driftDb.insertEntries({entry(4, dir: '/other')});

    final predicate = predicateForFilters({StoredAlbumFilter('/album', null)})!;
    final stats = await PagedStatsSource(predicate: predicate, entryCount: 3, chunkSize: 2).load();

    expect(stats.entryCount, 3);
    expect(stats.entryCountPerAlbum, {'/album': 3});
  });

  test('the export stream carries every row, with its metadata attached', () async {
    await seed();
    const source = PagedStatsSource(predicate: CollectionWindowPredicate(), entryCount: 3, chunkSize: 2);

    final entries = <AvesEntry>[];
    await for (final chunk in source.streamEntries()) {
      expect(chunk.length, lessThanOrEqualTo(2));
      entries.addAll(chunk);
    }
    expect(entries.map((entry) => entry.id), [1, 2, 3]);

    final first = entries.firstWhere((entry) => entry.id == 1);
    expect(first.mimeType, 'image/heic');
    expect(first.rating, 4);
    expect(first.tags, {'sunset', 'beach'});
    expect(first.hasGps, isTrue);
    expect(first.shortAddress, isNotEmpty);
  });

  test('the export preview reads the first row of the scope', () async {
    await seed();
    const source = PagedStatsSource(predicate: CollectionWindowPredicate(), entryCount: 3);

    final first = await source.firstEntry();
    expect(first?.id, 1);
    expect(first?.mimeType, 'image/heic');
  });

  test('a small library keeps the in-memory path', () async {
    await seed();
    await collectionPagingPrefs.setLargeThreshold(1000);
    expect(await pagedStatsSourceFor({}), isNull);
  });

  test('a large library streams its stats', () async {
    await seed();
    await collectionPagingPrefs.setLargeThreshold(1);
    final source = await pagedStatsSourceFor({});
    expect(source, isNotNull);
    expect(source!.entryCount, 3);
  });
}
