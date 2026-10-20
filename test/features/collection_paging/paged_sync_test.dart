import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_bootstrap.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../fake/media_fetch_service.dart';
import '../../helpers/sqlite3_loader.dart';

/// Paged sync (fresh discovery + changed-based sync) and paged mutation
/// (delete without materializing), against an in-memory Drift database.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
  });

  late AppDatabase db;
  late DriftLocalMediaDb driftDb;
  late MediaStoreSource source;

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
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearTrashDetails();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
  });

  AvesEntry entry(
    int id, {
    String dir = '/album',
    int? contentId,
    bool trashed = false,
  }) {
    contentId ??= 100 + id;
    return AvesEntry(
      id: id,
      uri: 'content://media/external/images/media/$contentId',
      path: '$dir/$id.jpg',
      contentId: contentId,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  group('PagedDiscoverer.importAll', () {
    test('inserts streamed rows in chunks and resumes', () async {
      final store = _ScriptedMediaStore()..entries = {for (var id = 1; id <= 5; id++) entry(id)};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      var progress = 0;
      expect(await discoverer.importAll(onProgress: (_) => progress++), 5);
      expect(await driftDb.countEntries(), 5);
      expect(progress, greaterThan(0));

      // Reruns skip known rows instead of duplicating.
      expect(await discoverer.importAll(onProgress: (_) {}), 0);
      expect(await driftDb.countEntries(), 5);
    });

    test('hands the written rows over for surfaces that browse before indexing', () async {
      final store = _ScriptedMediaStore()..entries = {for (var id = 1; id <= 4; id++) entry(id)};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      final handed = <int>[];
      await discoverer.importAll(onProgress: (_) {}, onRows: (rows) => handed.addAll(rows.map((v) => v.id)));

      // Every row arrives once, under the id the database kept, so a browser
      // fed by the import and one fed by a later scan agree on identity.
      expect(handed, hasLength(4));
      expect(handed.toSet(), hasLength(4));
      expect(await driftDb.loadEntriesById(handed.toSet()), hasLength(4));
    });

    test('signals the first batch before the rest is written', () async {
      final store = _ScriptedMediaStore()..entries = {for (var id = 1; id <= 10; id++) entry(id)};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      var atSignal = -1;
      var done = 0;
      final imported = await discoverer.importAll(
        onProgress: (processed) => done = processed,
        firstBatchLimit: 3,
        onFirstBatch: () async => atSignal = done,
      );
      // The caller paints with the first batch in hand, not with the whole run.
      expect(atSignal, 3);
      // ...and the stream carries on behind it to the end.
      expect(imported, 10);
      expect(done, 10);
      expect(await driftDb.countEntries(), 10);
    });

    test('still signals when the library is smaller than one batch', () async {
      final store = _ScriptedMediaStore()..entries = {for (var id = 1; id <= 2; id++) entry(id)};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      var signals = 0;
      await discoverer.importAll(
        onProgress: (_) {},
        firstBatchLimit: 500,
        onFirstBatch: () async => signals++,
      );
      expect(signals, 1);
      expect(await driftDb.countEntries(), 2);
    });

    test('counts the rows the stream would cover, not only the new ones', () async {
      final store = _ScriptedMediaStore()..entries = {for (var id = 1; id <= 4; id++) entry(id)};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      expect(await discoverer.countEntries(), 4);
      await discoverer.importAll(onProgress: (_) {});
      // A resumed run re-walks known rows: the counter must stay monotonic
      // instead of reading 0 while it re-checks them.
      var done = 0;
      await discoverer.importAll(onProgress: (processed) => done = processed);
      expect(done, 4);
    });
  });

  group('PagedDiscoverer.syncIfChanged', () {
    test('is a no-op when the generation is unchanged', () async {
      final store = _ScriptedMediaStore()..generation = {'primary': 7};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb)..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 0);
      expect(await driftDb.countEntries(), 0);
    });

    test('baselines an unknown generation without backfilling', () async {
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 7}
        ..changedUris = ['content://media/external/images/media/111'];
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);
      expect(await discoverer.syncIfChanged(), 0);
      expect(await driftDb.countEntries(), 0);
      expect(discoverer.lastGeneration, {'primary': 7});
    });

    test('inserts changed files', () async {
      final fresh = entry(1);
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [fresh.uri];
      final fetch = FakeMediaFetchService()..entries = {fresh};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 1);
      expect(discoverer.lastGeneration, {'primary': 8});
    });

    test('catalogs synced files inline', () async {
      final fresh = entry(1);
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [fresh.uri];
      final fetch = FakeMediaFetchService()..entries = {fresh};
      final cataloguedIds = <int>[];
      final discoverer = PagedDiscoverer(
        mediaStore: store,
        mediaFetch: fetch,
        database: driftDb,
        catalogEntry: (entry) async {
          cataloguedIds.add(entry.id);
          entry.catalogMetadata = CatalogMetadata(id: entry.id, xmpSubjects: 'fresh');
          await driftDb.updateCatalogMetadata(entry.id, entry.catalogMetadata);
        },
      )..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 1);
      expect(cataloguedIds, hasLength(1));
      expect((await driftDb.loadCatalogMetadata()).single.xmpSubjects, 'fresh');
      expect(await driftDb.countUncatalogued(), 0);
    });

    test('removes obsolete files', () async {
      await driftDb.insertEntries({entry(1)});
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = ['content://media/external/images/media/101']
        ..obsoleteContentIds = [101];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})
        ..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 0);
    });

    test('ignores unresolvable changes', () async {
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = ['content://media/external/images/media/999'];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})
        ..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 0);
      expect(await driftDb.countEntries(), 0);
    });
  });

  group('paged mutation', () {
    test('removeEntries deletes from the database without materializing', () async {
      await PagedBootstrap.ensure(source);
      await driftDb.insertEntries({entry(1), entry(2)});
      expect(source.allEntries, isEmpty);

      await source.removeEntries({'content://media/external/images/media/101'}, includeTrash: false);
      expect(await driftDb.countEntries(), 1);
      final remaining = await driftDb.loadEntriesByUris({'content://media/external/images/media/102'});
      expect(remaining.single.id, 2);
    });

    test('cleanEmptyAlbums keeps directories on an entry-free source', () async {
      source.addDirectories(albums: {'/a', '/b'});
      expect(source.rawAlbums, containsAll(['/a', '/b']));
      source.cleanEmptyAlbums();
      expect(source.rawAlbums, containsAll(['/a', '/b']));
    });
  });
}

class _ScriptedMediaStore extends Fake implements MediaStoreService {
  Set<AvesEntry> entries = {};
  Map<String, int>? generation;
  List<String> changedUris = const [];
  List<int> obsoleteContentIds = const [];

  @override
  Future<Map<String, int>?> getGenerationByVolume() async => generation;

  @override
  Future<List<String>> getChangedUris(Map<String, int?> sinceGenerationByVolume) async => changedUris;

  @override
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds) async => obsoleteContentIds;

  @override
  Stream<AvesEntry> getEntries(Map<int?, int?> knownEntries, {String? directory}) => Stream.fromIterable(entries);

  @override
  Future<int> countEntries() async => entries.length;
}
