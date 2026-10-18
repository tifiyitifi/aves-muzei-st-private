import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Catalog coverage queries against an in-memory Drift database: keyset
/// pagination over entries missing metadata (to catalog) or missing addresses
/// despite having coordinates (to locate). Drives the paged background worker
/// without ever materializing entries.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
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

  AvesEntry entry(int id, {String dir = '/album', bool trashed = false}) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$dir/$id.jpg',
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
      sourceDateTakenMillis: 0,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  CatalogMetadata metadata(int id, {double? latitude, double? longitude}) => CatalogMetadata(
        id: id,
        latitude: latitude,
        longitude: longitude,
      );

  group('catalog coverage', () {
    /// The ids of a sweep page, in the order the sweep returns them.
    Future<List<int>> pageIds({CollectionWindowPredicate? predicate, BacklogCursor? after, int limit = 10}) async {
      final page = await service.loadUncataloguedEntryIds(predicate: predicate ?? const CollectionWindowPredicate(), after: after ?? LocalMediaDb.backlogStart, limit: limit);
      return [for (final cursor in page) cursor.id];
    }

    test('lists entries missing metadata with keyset pagination', () async {
      await service.insertEntries({for (var i = 1; i <= 5; i++) entry(i)});
      await service.saveCatalogMetadata({metadata(2), metadata(4)});

      expect(await service.countUncatalogued(), 3);
      expect(await pageIds(limit: 2), [1, 3]);
      expect(await pageIds(after: (directory: '/album', id: 3)), [5]);
      expect(await pageIds(after: (directory: '/album', id: 5)), isEmpty);
    });

    test('sweeps album by album, with a cursor inside an album', () async {
      await service.insertEntries({entry(1, dir: '/b'), entry(2, dir: '/a'), entry(3, dir: '/a')});

      // Album-then-id order: a sweep finishes an album before moving on, so a
      // resumed run continues at a natural boundary.
      expect(await pageIds(), [2, 3, 1]);
      expect(await pageIds(after: (directory: '/a', id: 2)), [3, 1]);
      expect(await pageIds(after: (directory: '/a', id: 3)), [1]);
    });

    test('counts zero on empty or fully catalogued libraries', () async {
      expect(await service.countUncatalogued(), 0);
      expect(await pageIds(), isEmpty);

      await service.insertEntries({entry(1)});
      await service.saveCatalogMetadata({metadata(1)});
      expect(await service.countUncatalogued(), 0);
    });

    test('limits the catalog backlog to a scope', () async {
      await service.insertEntries({entry(1), entry(2, dir: '/other'), entry(3, dir: '/other'), entry(4, trashed: true)});
      final scope = predicateForFilters({StoredAlbumFilter('/other', null)})!;

      // The scope sees its own rows only; the backlog itself stays complete,
      // trashed rows included (the legacy analyze catalogues them too).
      expect(await service.countUncatalogued(scope), 2);
      expect(await pageIds(predicate: scope), [2, 3]);
      expect(await service.countUncatalogued(), 4);
      // Album buckets in order, ids inside each: the scope's rows come last.
      expect(await pageIds(), [1, 4, 2, 3]);
    });

    test('limits the locate backlog to a scope', () async {
      await service.insertEntries({entry(1), entry(2, dir: '/other')});
      await service.saveCatalogMetadata({
        metadata(1, latitude: 1, longitude: 1),
        metadata(2, latitude: 1, longitude: 1),
      });
      final scope = predicateForFilters({StoredAlbumFilter('/other', null)})!;

      expect((await service.loadUnaddressedGpsIds(predicate: scope, after: LocalMediaDb.backlogStart, limit: 10)).map((c) => c.id), [2]);
      expect((await service.loadUnlocatedGpsIds(predicate: scope, after: LocalMediaDb.backlogStart, limit: 10)).map((c) => c.id), [2]);
    });

    test('lists gps entries missing addresses with keyset pagination', () async {
      await service.insertEntries({for (var i = 1; i <= 4; i++) entry(i)});
      await service.saveCatalogMetadata({
        metadata(1, latitude: 1, longitude: 1),
        metadata(2, latitude: 2, longitude: 2),
        metadata(3),
      });
      await service.saveAddresses({
        const AddressDetails(id: 1, countryCode: 'FR', locality: 'Paris'),
      });

      // id 3 has no coordinates, id 4 has no metadata row at all
      expect((await service.loadUnaddressedGpsIds(after: LocalMediaDb.backlogStart, limit: 10)).map((c) => c.id), [2]);
      expect(await service.loadUnaddressedGpsIds(after: (directory: '/album', id: 2), limit: 10), isEmpty);
    });

    test('lists gps entries missing fine addresses, including country-only rows', () async {
      await service.insertEntries({for (var i = 1; i <= 4; i++) entry(i)});
      await service.saveCatalogMetadata({
        metadata(1, latitude: 1, longitude: 1),
        metadata(2, latitude: 2, longitude: 2),
        metadata(3, latitude: 3, longitude: 3),
        metadata(4),
      });
      await service.saveAddresses({
        // country-only row (offline-country pass output): still needs places
        const AddressDetails(id: 1, countryCode: 'FR', countryName: 'FRA'),
        // fine row: done
        const AddressDetails(id: 2, countryCode: 'US', countryName: 'United States', adminArea: 'California', locality: 'SF'),
      });

      // id 1 (country-only) and id 3 (no address row); id 2 fine, id 4 no gps
      expect((await service.loadUnlocatedGpsIds(after: LocalMediaDb.backlogStart, limit: 10)).map((c) => c.id), [1, 3]);
      expect((await service.loadUnlocatedGpsIds(after: (directory: '/album', id: 1), limit: 10)).map((c) => c.id), [3]);
      expect(await service.loadUnlocatedGpsIds(after: (directory: '/album', id: 3), limit: 10), isEmpty);
    });
  });
}
