import 'package:aves/features/collection_paging/catalog/paged_catalog_worker.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/location/location.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/model/source/tag.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// Paged background catalog + offline-country worker, against an in-memory
/// Drift database with injected (fake) per-entry functions: chunked progress,
/// batch commits, cooperative stop, and resume-after-interruption.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late AppDatabase db;
  late DriftLocalMediaDb database;
  late MediaStoreSource source;

  setUp(() async {
    await setUpServices();
    db = AppDatabase(NativeDatabase.memory());
    database = DriftLocalMediaDb(database: db);
    await database.init();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
    await db.close();
  });

  AvesEntry entry(int id, {String dir = '/album'}) {
    return AvesEntry(
      id: id,
      uri: 'content://media/external/images/media/${100 + id}',
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
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  PagedCatalogWorker worker({
    Future<void> Function(AvesEntry entry)? catalogEntry,
    Future<AddressDetails?> Function(AvesEntry entry)? locateCountry,
    Future<AddressDetails?> Function(AvesEntry entry)? locatePlaces,
    Future<bool> Function()? canLocate,
  }) =>
      PagedCatalogWorker(
        source: source,
        database: database,
        catalogEntry: catalogEntry ?? ((entry) async => entry.catalogMetadata = CatalogMetadata(id: entry.id, xmpSubjects: 't')),
        locateCountry: locateCountry,
        locatePlaces: locatePlaces,
        canLocate: canLocate,
      );

  group('PagedCatalogWorker', () {
    test('catalogs the backlog in chunks and notifies', () async {
      await database.insertEntries({for (var i = 1; i <= 5; i++) entry(i)});
      var catalogEvents = 0;
      final sub = source.eventBus.on<CatalogMetadataChangedEvent>().listen((_) => catalogEvents++);
      addTearDown(sub.cancel);

      final w = worker();
      await w.run(chunkSize: 2);
      expect(w.isRunning, isFalse);
      expect(await database.countUncatalogued(), 0);
      expect((await database.loadCatalogMetadata()).length, 5);
      expect(catalogEvents, greaterThan(0));

      // reruns are no-ops
      await w.run(chunkSize: 2);
      expect(await database.countUncatalogued(), 0);
    });

    test('catalogs the view scope before the rest of the backlog', () async {
      await database.insertEntries({entry(1), entry(2, dir: '/other'), entry(3, dir: '/other')});
      final scope = predicateForFilters({StoredAlbumFilter('/other', null)})!;
      final order = <int>[];
      final w = worker(
        catalogEntry: (entry) async {
          order.add(entry.id);
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
        },
      );

      await w.run(chunkSize: 10, scope: scope);

      // The scope's rows go first, in id order; the unscoped pass then picks up
      // what the scope did not cover.
      expect(order, [2, 3, 1]);
      expect(await database.countUncatalogued(), 0);
    });

    test('resumes the saved frontier and wraps to cover what precedes it', () async {
      await database.insertEntries({for (var i = 1; i <= 3; i++) entry(i, dir: '/d$i')});
      // A frontier from an earlier session: the sweep must continue after it and
      // then wrap, or the rows before it would never be catalogued.
      await database.saveCatalogCursor((directory: '/d1', id: 1));
      final order = <int>[];
      final w = worker(
        catalogEntry: (entry) async {
          order.add(entry.id);
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
        },
      );

      await w.run(chunkSize: 10);

      expect(order, [2, 3, 1]);
      expect(await database.countUncatalogued(), 0);
    });

    test('a scoped pass keeps the library sweep out of its own rows', () async {
      await database.insertEntries({entry(1), entry(2, dir: '/other')});
      await database.saveCatalogCursor((directory: '/album', id: 1));
      final scope = predicateForFilters({StoredAlbumFilter('/other', null)})!;
      final order = <int>[];
      final w = worker(
        catalogEntry: (entry) async {
          order.add(entry.id);
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
        },
      );

      await w.run(chunkSize: 10, scope: scope);

      // The scope's row is catalogued by the scoped pass, once, before the
      // library pass resumes at its saved frontier.
      expect(order, [2, 1]);
      expect(await database.countUncatalogued(), 0);
    });

    test('a scoped-only pass leaves the rest of the library alone', () async {
      await database.insertEntries({entry(1), entry(2, dir: '/other'), entry(3, dir: '/other')});
      final scope = predicateForFilters({StoredAlbumFilter('/other', null)})!;
      final order = <int>[];
      final w = worker(
        catalogEntry: (entry) async {
          order.add(entry.id);
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
        },
      );

      // Another owner (the analysis service) is taking the rest of the library,
      // so this pass serves only the view the user is in.
      await w.run(chunkSize: 10, scope: scope, scopedOnly: true);

      expect(order, [2, 3]);
      expect(await database.countUncatalogued(), 1);
    });

    test('stop halts between chunks and resumes after', () async {
      await database.insertEntries({for (var i = 1; i <= 6; i++) entry(i)});
      late PagedCatalogWorker w;
      var calls = 0;
      w = worker(
        catalogEntry: (entry) async {
          calls++;
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
          if (calls == 3) w.stop();
        },
      );
      await w.run(chunkSize: 2);
      final done = await database.countUncatalogued();
      expect(done, greaterThan(0));
      expect(done, lessThan(6));

      await worker().run(chunkSize: 2);
      expect(await database.countUncatalogued(), 0);
    });

    test('skips poisoned entries and keeps going', () async {
      await database.insertEntries({for (var i = 1; i <= 3; i++) entry(i)});
      final w = worker(
        catalogEntry: (entry) async {
          if (entry.id == 2) throw StateError('poison');
          entry.catalogMetadata = CatalogMetadata(id: entry.id);
        },
      );
      await w.run(chunkSize: 10);
      expect((await database.loadCatalogMetadata()).map((m) => m.id), {1, 3});
      // the poisoned row stays uncatalogued for the next run
      expect(await database.countUncatalogued(), 1);
    });

    test('locates offline countries for gps rows', () async {
      await database.insertEntries({for (var i = 1; i <= 3; i++) entry(i)});
      await database.saveCatalogMetadata({
        CatalogMetadata(id: 1, latitude: 48.8, longitude: 2.3),
        CatalogMetadata(id: 2, latitude: 40.7, longitude: -74.0),
        CatalogMetadata(id: 3),
      });
      var addressEvents = 0;
      final sub = source.eventBus.on<AddressMetadataChangedEvent>().listen((_) => addressEvents++);
      addTearDown(sub.cancel);

      final locatedIds = <int>[];
      final w = worker(
        catalogEntry: (entry) async => entry.catalogMetadata ??= CatalogMetadata(id: entry.id),
        locateCountry: (entry) async {
          // proves the worker attached metadata: only gps rows arrive here
          expect(entry.hasGps, isTrue);
          locatedIds.add(entry.id);
          return AddressDetails(id: entry.id, countryCode: 'FR', countryName: 'France');
        },
      );
      await w.run(chunkSize: 2);
      expect(locatedIds.toSet(), {1, 2});
      expect((await database.loadAddresses()).length, 2);
      expect(addressEvents, greaterThan(0));
      expect(await database.loadUnaddressedGpsIds(after: LocalMediaDb.backlogStart, limit: 10), isEmpty);
    });

    test('runPlaces skips when locating is unavailable', () async {
      await database.insertEntries({entry(1)});
      await database.saveCatalogMetadata({CatalogMetadata(id: 1, latitude: 48.8, longitude: 2.3)});
      // FakeAvesAvailability.canLocatePlaces is false in tests
      final w = worker(
        catalogEntry: (entry) async => entry.catalogMetadata ??= CatalogMetadata(id: entry.id),
        locatePlaces: (entry) async {
          fail('must not geocode when locating is unavailable');
        },
      );
      await w.runPlaces(chunkSize: 10);
      expect(await database.loadAddresses(), isEmpty);
    });

    test('runPlaces fills fine addresses for unlocated gps rows', () async {
      await database.insertEntries({for (var i = 1; i <= 3; i++) entry(i)});
      await database.saveCatalogMetadata({
        CatalogMetadata(id: 1, latitude: 48.8, longitude: 2.3),
        CatalogMetadata(id: 2, latitude: 40.7, longitude: -74.0),
        CatalogMetadata(id: 3),
      });
      await database.saveAddresses({
        const AddressDetails(id: 1, countryCode: 'FR', countryName: 'FRA'),
      });
      var addressEvents = 0;
      final sub = source.eventBus.on<AddressMetadataChangedEvent>().listen((_) => addressEvents++);
      addTearDown(sub.cancel);

      final locatedIds = <int>[];
      final w = worker(
        canLocate: () async => true,
        locatePlaces: (entry) async {
          locatedIds.add(entry.id);
          return AddressDetails(id: entry.id, countryCode: 'FR', countryName: 'France', adminArea: 'Ile-de-France', locality: 'Paris');
        },
      );
      await w.runPlaces(chunkSize: 2);
      // id 1 (country-only) and id 2 (no address); id 3 has no gps
      expect(locatedIds.toSet(), {1, 2});
      expect((await database.loadAddresses()).length, 2);
      expect(addressEvents, greaterThan(0));
      expect(await database.loadUnlocatedGpsIds(after: LocalMediaDb.backlogStart, limit: 10), isEmpty);
    });
  });
}
