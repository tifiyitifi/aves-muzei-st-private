import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
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

  AvesEntry entry(int id) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '/album/$id.jpg',
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
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  CatalogMetadata metadata(int id, {double? latitude, double? longitude}) => CatalogMetadata(
        id: id,
        latitude: latitude,
        longitude: longitude,
      );

  group('catalog coverage', () {
    test('lists entries missing metadata with keyset pagination', () async {
      await service.insertEntries({for (var i = 1; i <= 5; i++) entry(i)});
      await service.saveCatalogMetadata({metadata(2), metadata(4)});

      expect(await service.countUncatalogued(), 3);
      expect(await service.loadUncataloguedEntryIds(afterId: 0, limit: 2), [1, 3]);
      expect(await service.loadUncataloguedEntryIds(afterId: 3, limit: 10), [5]);
      expect(await service.loadUncataloguedEntryIds(afterId: 5, limit: 10), isEmpty);
    });

    test('counts zero on empty or fully catalogued libraries', () async {
      expect(await service.countUncatalogued(), 0);
      expect(await service.loadUncataloguedEntryIds(afterId: 0, limit: 10), isEmpty);

      await service.insertEntries({entry(1)});
      await service.saveCatalogMetadata({metadata(1)});
      expect(await service.countUncatalogued(), 0);
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
      expect(await service.loadUnaddressedGpsIds(afterId: 0, limit: 10), [2]);
      expect(await service.loadUnaddressedGpsIds(afterId: 2, limit: 10), isEmpty);
    });
  });
}
