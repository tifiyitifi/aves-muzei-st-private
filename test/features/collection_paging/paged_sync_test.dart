import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_paging_keys.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../fake/media_fetch_service.dart';
import '../../helpers/sqlite3_loader.dart';

/// Paged sync (fresh discovery + changed-based sync) and paged mutation
/// (delete without materializing), against an in-memory Drift database.
void main() {
  late _RecordingPrefsStore prefsStore;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
    // Installed after the shared services, which reset the store themselves. The
    // recorder lets a test tell the retry list's write from the cursor's.
    SharedPreferencesStorePlatform.instance = prefsStore = _RecordingPrefsStore();
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
    // The cursor and the retry list are process-wide: a test must not inherit
    // the previous one's snapshot.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(CollectionPagingKeys.mediaGeneration);
    await prefs.remove(CollectionPagingKeys.pendingSyncUris);
    prefsStore.writes.clear();
    prefsStore.failingKeys.clear();
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearTrashDetails();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    // A failing key would take the settings writes of the next test down with it.
    prefsStore.failingKeys.clear();
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

    test('imports rows a provider reports without a content id', () async {
      // Batches used to be keyed by content id only, so such a row was dropped
      // by the import while the change sync inserted it later: same row, two
      // answers. The URI identifies it just as well.
      final withoutContentId = AvesEntry(
        id: 2,
        uri: 'content://media/external/images/media/2',
        path: '/album/2.jpg',
        contentId: null,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: 5,
        sourceTitle: 'title2',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );
      final store = _ScriptedMediaStore()..entries = {entry(1), withoutContentId};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 2);
      expect(await driftDb.countEntries(), 2);

      // A rerun matches it by URI instead of inserting a duplicate.
      expect(await discoverer.importAll(onProgress: (_) {}), 0);
      expect(await driftDb.countEntries(), 2);
    });

    test('keeps the newest of repeated rows in one batch', () async {
      // Rows are streamed newest first, but a provider can repeat one. The
      // identity must keep the newest report, not the last one the map saw.
      final newest = entry(1)..dateModifiedMillis = 20;
      final older = entry(2)
        ..contentId = newest.contentId
        ..uri = newest.uri
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()..entries = {newest, older};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 1);
      expect(await driftDb.countEntries(), 1);
      final stored = (await driftDb.loadEntriesByContentIds({newest.contentId!})).single;
      expect(stored.path, newest.path, reason: 'the older duplicate must not win');
      expect(stored.dateModifiedMillis, 20);
    });

    test('merges a file repeated in one batch under both identities', () async {
      // A repeated row can arrive once with a content id and once without. Keyed
      // separately by id and by URI, the two reports each reached the insert, and
      // nothing in the schema stops two rows for one file.
      final withId = entry(1)..dateModifiedMillis = 20;
      final withoutId = entry(2)
        ..contentId = null
        ..uri = withId.uri
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()..entries = {withId, withoutId};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 1);
      expect(await driftDb.countEntries(), 1);
      final stored = (await driftDb.loadEntriesByUris({withId.uri})).single;
      expect(stored.contentId, withId.contentId);
      expect(stored.dateModifiedMillis, 20);
    });

    test('keeps the id when the report without one wins the merge', () async {
      // The newer report is the one without an id: it wins, but the id the other
      // report carried has to survive with it, or the stored row loses the
      // identity the change sync keys on.
      final withId = entry(1)..dateModifiedMillis = 10;
      final newerWithoutId = entry(2)
        ..contentId = null
        ..uri = withId.uri
        ..dateModifiedMillis = 20;
      final store = _ScriptedMediaStore()..entries = {withId, newerWithoutId};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 1);
      final stored = (await driftDb.loadEntriesByUris({withId.uri})).single;
      expect(stored.dateModifiedMillis, 20);
      expect(stored.contentId, withId.contentId, reason: 'the winning report inherits the identity');
    });

    test('keeps the content id a stored row already had', () async {
      // The provider reports the same URI without an id on a later pass. URI
      // matching is a fallback, not a reason to forget the identity the row
      // already has: losing it would make a legacy refresh insert the file
      // again under a second row.
      final stored = entry(1);
      await driftDb.insertEntries({stored});
      final replayed = entry(1)
        ..contentId = null
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()..entries = {replayed};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 1);
      expect(await driftDb.countEntries(), 1);
      final row = (await driftDb.loadEntriesByUris({stored.uri})).single;
      expect(row.contentId, stored.contentId, reason: 'uri matching must not degrade the stored identity');
    });

    test('fails instead of hanging when the media store stream goes silent', () async {
      final controller = StreamController<AvesEntry>();
      addTearDown(controller.close);
      final store = _ScriptedMediaStore()..entriesStream = controller.stream;
      final discoverer = PagedDiscoverer(
        mediaStore: store,
        database: driftDb,
        streamIdleTimeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        discoverer.importAll(onProgress: (_) {}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('imports rows that all report a zero content id', () async {
      // A provider with no ids hands back 0 for every row: keying the batch by
      // content id would collapse them into one and lose the rest.
      final store = _ScriptedMediaStore()
        ..entries = {
          entry(1)..contentId = 0,
          entry(2)..contentId = 0,
        };
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      expect(await discoverer.importAll(onProgress: (_) {}), 2);
      expect(await driftDb.countEntries(), 2);
    });

    test('stores a cursor a change during the scan is still newer than', () async {
      // The stream is ordered newest first: a file that lands while the scan
      // runs is behind the cursor it has already passed. A cursor taken at the
      // end of the run would claim that change had been applied, and the sync
      // would never offer it again.
      final store = _ScriptedMediaStore()
        ..entries = {for (var id = 1; id <= 4; id++) entry(id)}
        ..generation = {'primary': 5};
      final discoverer = PagedDiscoverer(mediaStore: store, database: driftDb);

      await discoverer.importAll(
        onProgress: (_) {},
        firstBatchLimit: 2,
        onFirstBatch: () async => store.generation = {'primary': 9},
      );

      expect(discoverer.lastGeneration, {'primary': 5}, reason: 'the change during the scan must stay readable');
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

    test('retries a change a transient failure left behind instead of losing it', () async {
      final fresh = entry(1);
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [fresh.uri];
      final fetch = FakeMediaFetchService()
        ..entries = {fresh}
        ..failingUris = {fresh.uri};
      final first = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await first.syncIfChanged(), 0);
      expect(await driftDb.countEntries(), 0);
      expect(first.lastGeneration, {'primary': 8}, reason: 'the read itself completed');
      expect(first.pendingUris, {fresh.uri}, reason: 'the change is owed, not dropped');

      // A later sync with the same generation must still offer the failed URI,
      // even across a restart: the list is persisted next to the cursor.
      fetch.failingUris = {};
      final second = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {});
      expect(await second.syncIfChanged(), 1);
      expect((await driftDb.loadEntriesByUris({fresh.uri})).single.dateModifiedMillis, fresh.dateModifiedMillis);
      expect(second.pendingUris, isEmpty);
    });

    test('writes the retry list before the cursor that would hide it', () async {
      // The two writes cannot be atomic. Landing the cursor first leaves the
      // change set behind it, so a process death between them loses the retry
      // the list exists to keep.
      final fresh = entry(1);
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [fresh.uri];
      final fetch = FakeMediaFetchService()
        ..entries = {fresh}
        ..failingUris = {fresh.uri};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      await discoverer.syncIfChanged();

      final pendingAt = prefsStore.writes.indexOf(CollectionPagingKeys.pendingSyncUris);
      final generationAt = prefsStore.writes.indexOf(CollectionPagingKeys.mediaGeneration);
      expect(pendingAt, isNonNegative, reason: 'the failed uri must be persisted');
      expect(generationAt, greaterThan(pendingAt), reason: 'the cursor may only move once the retry is on disk');
    });

    test('keeps the cursor when the retry list cannot be persisted', () async {
      // A write the platform rejects is the same loss as a crash between the two:
      // the failed change has nowhere to be retried from, so the cursor has to
      // stay where the change set can be read again.
      final fresh = entry(1);
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [fresh.uri];
      final fetch = FakeMediaFetchService()
        ..entries = {fresh}
        ..failingUris = {fresh.uri};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};
      prefsStore.failingKeys.add(CollectionPagingKeys.pendingSyncUris);

      expect(await discoverer.syncIfChanged(), 0);
      expect(discoverer.lastGeneration, {'primary': 7}, reason: 'the whole change set is re-read next time');
      expect(discoverer.pendingUris, {fresh.uri});
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
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};
      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 0);
    });

    test('updates a changed row without a content id by URI instead of inserting it again', () async {
      final known = entry(1)..contentId = null;
      await driftDb.insertEntries({known});
      final changed = entry(1)
        ..contentId = null
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [changed.uri];
      final fetch = FakeMediaFetchService()..entries = {changed};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 1);
      expect((await driftDb.loadEntriesByUris({changed.uri})).single.dateModifiedMillis, 10);
    });

    test('removes an obsolete row that was stored without a content id', () async {
      final known = entry(1)..contentId = null;
      await driftDb.insertEntries({known});
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [known.uri]
        ..obsoleteContentIds = [101];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 0);
    });

    test('treats a zero content id as absent', () async {
      final known = entry(1)..contentId = 0;
      await driftDb.insertEntries({known});
      final changed = entry(1)
        ..contentId = 0
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [changed.uri];
      final fetch = FakeMediaFetchService()..entries = {changed};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 1);
    });

    test('checks obsolescence once for the whole change set', () async {
      // The check scans the whole media store: a bulk delete must not cost one
      // full scan per deleted file.
      final one = entry(1), two = entry(2);
      await driftDb.insertEntries({one, two});
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [one.uri, two.uri]
        ..obsoleteContentIds = [101, 102];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 2);
      expect(await driftDb.countEntries(), 0);
      expect(store.obsoleteCheckCount, 1, reason: 'one platform scan for the whole change set');
    });

    test('removes a row whose id was handed to another file', () async {
      // Ids are not reuse-proof. The row was stored without a content id, and
      // its URI's id is live again for a different file: the path is what says
      // the stored row is the one that went away.
      final known = entry(1)..contentId = null;
      await driftDb.insertEntries({known});
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [known.uri]
        ..obsoleteContentIds = const []
        ..obsoletePaths = [101];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 1);
      expect(await driftDb.countEntries(), 0);
      expect(store.pathCheckCount, 1);
    });

    test('keeps a row whose live id still names the same file', () async {
      // `getEntry` can fail transiently while the file is there: the obsolete
      // check is the guard against deleting a live row over a bad read.
      final known = entry(1)..contentId = null;
      await driftDb.insertEntries({known});
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [known.uri]
        ..obsoleteContentIds = const []
        ..obsoletePaths = const [];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 0);
      expect(await driftDb.countEntries(), 1);
    });

    test('keeps the content id a row already had when the provider stops reporting it', () async {
      final known = entry(1);
      await driftDb.insertEntries({known});
      final changed = entry(1)
        ..contentId = null
        ..dateModifiedMillis = 10;
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = [known.uri];
      final fetch = FakeMediaFetchService()..entries = {changed};
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: fetch, database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};

      expect(await discoverer.syncIfChanged(), 1);
      final row = (await driftDb.loadEntriesByUris({known.uri})).single;
      expect(row.contentId, known.contentId, reason: 'uri matching must not degrade the stored identity');
    });

    test('ignores unresolvable changes', () async {
      final store = _ScriptedMediaStore()
        ..generation = {'primary': 8}
        ..changedUris = ['content://media/external/images/media/999'];
      final discoverer = PagedDiscoverer(mediaStore: store, mediaFetch: FakeMediaFetchService(), database: driftDb, catalogEntry: (_) async {})..lastGeneration = {'primary': 7};
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

  /// Ids the platform still carries but under another path, as
  /// `checkObsoletePaths` reports them (a reused id).
  List<int> obsoletePaths = const [];

  int obsoleteCheckCount = 0;
  int pathCheckCount = 0;

  /// When set, `getEntries` streams this instead of [entries], so a test can
  /// keep the stream open (or dead) and observe the import behavior.
  Stream<AvesEntry>? entriesStream;

  @override
  Future<Map<String, int>?> getGenerationByVolume() async => generation;

  @override
  Future<List<String>> getChangedUris(Map<String, int?> sinceGenerationByVolume) async => changedUris;

  @override
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds) async {
    obsoleteCheckCount++;
    return obsoleteContentIds;
  }

  @override
  Future<List<int>> checkObsoletePaths(Map<int?, String?> knownPathById) async {
    pathCheckCount++;
    return obsoletePaths;
  }

  @override
  Stream<AvesEntry> getEntries(Map<int?, int?> knownEntries, {String? directory}) => entriesStream ?? Stream.fromIterable(entries);

  @override
  Future<int> countEntries() async => entries.length;
}

/// Records the order preferences are written, and can reject one key.
///
/// The sync has two independent writes and no transaction between them, so a
/// test has to be able to see which one landed first, and to make the first one
/// fail the way a platform store can.
class _RecordingPrefsStore extends InMemorySharedPreferencesStore {
  new() : super.empty();

  final List<String> writes = [];
  final Set<String> failingKeys = {};

  // The legacy API prefixes every key it hands to the store.
  static const _prefix = 'flutter.';

  static String _logicalKey(String key) => key.startsWith(_prefix) ? key.substring(_prefix.length) : key;

  @override
  Future<bool> remove(String key) {
    final logical = _logicalKey(key);
    writes.add(logical);
    if (failingKeys.contains(logical)) throw StateError('preferences write failed for $key');
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final logical = _logicalKey(key);
    writes.add(logical);
    if (failingKeys.contains(logical)) throw StateError('preferences write failed for $key');
    return super.setValue(valueType, key, value);
  }
}
