import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/catalog/paged_catalog_worker.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/location/place.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/analysis_controller.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../fake/media_store_service.dart';
import '../../helpers/sqlite3_loader.dart';

/// Paged lens behaviour against an in-memory Drift database: auto morphing,
/// windowed reads with skeletons, blocking, and viewer copies.
void main() {
  // Attaching a windowed row's metadata goes through `AvesEntry.catalogMetadata`,
  // which evicts cached images (needs the binding) when the catalogued mime or
  // rotation differs from the source ones.
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await collectionPagingPrefs.setEngine(CollectionEngine.auto);
    await collectionPagingPrefs.setWindowSize(200);
    await collectionPagingPrefs.setPrefetchScreens(0);
    await collectionPagingPrefs.setLargeThreshold(100000);
    // Steady state: the library has been imported once. The import test below
    // turns this off on purpose.
    await collectionPagingPrefs.setImportComplete(true);
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearAddresses();
    await driftDb.clearTrashDetails();
    await db.customStatement('DELETE FROM appMeta WHERE key = ?', [DriftLocalMediaDb.importCompleteKey]);
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
  });

  AvesEntry entry(
    int id, {
    String dir = '/album',
    int dateTaken = 0,
    bool trashed = false,
  }) {
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
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  Future<void> settle(PagedCollectionLens lens, {required bool Function() done}) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('paged lens did not settle (entryCount=${lens.entryCount}, active=${lens.pagedActive}, blocked=${lens.pagedBlocked}, importing=${lens.importingRows}, state=${lens.source.state}, sections=${lens.sections.length}, loaded=${lens.loadedEntries.length})');
  }

  /// Reads every row, kicking off fetches like the sliver would, until none
  /// are skeletons. Non-empty is required: `every` is vacuously true on an
  /// empty list.
  bool allReal(PagedCollectionLens lens) => lens.sortedEntries.isNotEmpty && lens.sortedEntries.every((e) => e is! SkeletonEntry);

  Future<DriftLocalMediaDb> drift() async => getIt<LocalMediaDb>() as DriftLocalMediaDb;

  group('PagedCollectionLens', () {
    test('paints after the first import batch and settles ready when the rest lands', () async {
      // The import stream stays open so the two states can be observed: the
      // first batch is browsable, the source still says "organizing", and the
      // collection becomes whole when the stream ends.
      // The lens resolves the discoverer through the app-wide service, which is
      // bound on first use: set the stream on that instance, not on whatever
      // `getIt` holds after the latest registration.
      final store = mediaStoreService as FakeMediaStoreService;
      store.entries = {};
      final controller = StreamController<AvesEntry>();
      addTearDown(controller.close);
      store.entriesStream = controller.stream;
      // Page this small library: a below-threshold view morphs to legacy, which
      // has no import at all.
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setImportComplete(false);

      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);

      for (var id = 1; id <= CollectionPagingPrefs.firstImportBatchSize; id++) {
        controller.add(entry(id));
      }
      // The first batch is awaited by the lens, so `ready` resolves with rows on
      // screen and the import still running behind them.
      await lens.ready;
      expect(lens.entryCount, greaterThan(0));
      expect(lens.importingRows, isTrue);
      expect(source.state, SourceState.loading);

      controller.add(entry(CollectionPagingPrefs.firstImportBatchSize + 1));
      await controller.close();
      await settle(lens, done: () => !lens.importingRows && source.state == SourceState.ready);
      expect(lens.entryCount, CollectionPagingPrefs.firstImportBatchSize + 1);
    });

    test('morphs to legacy below the threshold', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 2);
      expect(lens.pagedActive, isFalse);
      expect(lens.pagedBlocked, isFalse);
      expect(lens.sortedEntries.every((e) => e is! SkeletonEntry), isTrue);
    });

    test('waits for a full load already in flight instead of starting a second one', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      // The home page starts loading the library before the collection page
      // mounts, so the lens finds a source that is still loading and has no scope
      // to report yet.
      final loading = _LoadingSource()
        ..canAnalyze = false
        ..state = SourceState.loading;
      final lens = PagedCollectionLens(source: loading, filters: {});
      addTearDown(lens.dispose);
      // A second full load here would dispose the entries the first pass is still
      // analysing, and would do the whole load twice: the lens has to wait.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(loading.initCount, 0);
      expect(lens.entryCount, 0);

      // The load lands: the lens serves what it loaded instead of reloading.
      await loading.completeLoad({entry(1), entry(2), entry(3)});
      await settle(lens, done: () => lens.entryCount == 3);
      expect(loading.initCount, 0);
      expect(lens.pagedActive, isFalse);
      expect(lens.pagedBlocked, isFalse);
    });

    test('pages above the threshold with lazy sections', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 1)), entry(3, dateTaken: millis(2024, 3, 5))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 3 && lens.pagedActive);
      expect(lens.sections.length, 2);
      // full-length lazy list: reads kick off fetches like the sliver would
      expect(lens.sortedEntries.length, 3);
      await settle(lens, done: () => lens.sortedEntries[0] is! SkeletonEntry);
      expect(lens.sortedEntries.whereType<SkeletonEntry>(), isNotEmpty);
      // loaded rows are real entries in display (date desc) order
      expect(lens.loadedEntries.map((e) => e.id), [3]);
    });

    test('an explicit legacy engine morphs even above the threshold', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await collectionPagingPrefs.setEngine(CollectionEngine.legacy);
      await collectionPagingPrefs.setLargeThreshold(1);
      // A scope the SQL layer cannot express would block under `auto`: the
      // explicit engine asks for the full load, so it is honoured instead.
      final lens = PagedCollectionLens(source: source, filters: {QueryFilter(r'/./', ACalendar.gregorian)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedBlocked || (!lens.pagedActive && lens.entryCount == 3));
      expect(lens.pagedBlocked, isFalse);
      expect(lens.pagedActive, isFalse);
      expect(lens.entryCount, 3);
    });

    test('unsupported filters block instead of crashing', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await collectionPagingPrefs.setLargeThreshold(2);
      // A `/regex/` query has no SQL translation, and the library cannot be fully
      // loaded: there is nothing left to serve, so the view is refused.
      final lens = PagedCollectionLens(source: source, filters: {QueryFilter(r'/./', ACalendar.gregorian)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedBlocked);
      expect(lens.entryCount, 0);
    });

    test('a narrow query pages instead of blocking when a full load is unsafe', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await collectionPagingPrefs.setLargeThreshold(2);
      // A live search is compiled like any plain title query, so a scope below
      // the threshold is paged: an empty result is a normal empty view, not the
      // unsupported notice.
      final lens = PagedCollectionLens(source: source, filters: {QueryFilter('zzz-no-match', ACalendar.gregorian, live: true)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive);
      expect(lens.pagedBlocked, isFalse);
      expect(lens.entryCount, 0);
    });

    test('a small scope pages instead of blocking when a full load is unsafe', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2, dir: '/other'), entry(3, dir: '/other')});
      // The view holds one row, the library three: a full load would materialize
      // the library to show one album, so the scope is served windowed instead.
      await collectionPagingPrefs.setLargeThreshold(2);
      final lens = PagedCollectionLens(source: source, filters: {StoredAlbumFilter('/album', null)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 1);
      expect(lens.pagedBlocked, isFalse);
      expect(lens.sections.length, 1);
      expect(lens.sortedEntries.length, 1);
    });

    test('viewer copies resolve across windows instead of snapshotting', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.loadedEntries.length == 2);
      final viewer = lens.copyWith(listenToSource: false);
      addTearDown(viewer.dispose);
      expect(viewer, isA<PagedViewerCopy>());
      final copy = viewer as PagedViewerCopy;
      expect(copy.entryCount, 2);
      expect(copy.sortedEntries.length, 2);
      expect(copy.globalIndexOf(lens.loadedEntries.first), 0);
      expect(copy.entryAt(1).id, 1);
    });

    test('a lookup finds a loaded tile without paging the library in', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.loadedEntries.length == 2);

      expect((await lens.firstMatching((entry) => entry.uri == 'content://2'))?.id, 2);
      expect(await lens.firstMatching((entry) => entry.uri == 'content://none'), isNull);
    });

    test('a lookup resolves a row outside the loaded windows and materializes it', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 2)), entry(3, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.sortedEntries[0] is! SkeletonEntry);

      // Scanning the lazy list instead would kick a fetch per index and answer
      // with a skeleton; the database walk answers with the real row, loaded.
      final found = await lens.firstMatching((entry) => entry.id == 1);
      expect(found?.id, 1);
      expect(found, isNot(isA<SkeletonEntry>()));
      expect(lens.sortedEntries.indexOf(found!), 2);
      expect(await lens.indexOfEntry(found), 2);
    });

    test('a lookup that arrives before the first load still resolves', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 2))});
      await collectionPagingPrefs.setLargeThreshold(2);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      // No settle: a page asks for its init highlight as soon as it opens.
      expect((await lens.firstMatching((entry) => entry.id == 2))?.id, 2);
    });

    test('a viewer copy resolves positions through its parent, shuffle included', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 2)), entry(3, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.sortedEntries[0] is! SkeletonEntry);

      final viewer = PagedViewerCopy(parent: lens, shuffleSeed: 7);
      addTearDown(viewer.dispose);
      final index = await viewer.indexOfEntry(entry(1));
      expect(index, inInclusiveRange(0, 2));
      // The copy's index space is the shuffled one, so the position must map
      // back to the same row.
      await viewer.prefetchAround(index);
      expect(viewer.entryAt(index).id, 1);
      // A lookup is answered by the parent, never by walking the copy itself.
      expect((await viewer.firstMatching((entry) => entry.id == 2))?.id, 2);
    });

    test('window rows carry the deep metadata an in-memory row carries', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 2))});
      await service.saveCatalogMetadata({
        CatalogMetadata(id: 1, rating: 4, xmpSubjects: 'red;blue', latitude: 48.8, longitude: 2.3, mimeType: 'image/heic'),
      });
      await service.saveAddresses({const AddressDetails(id: 1, countryCode: 'FR', countryName: 'France', adminArea: 'IDF', locality: 'Paris')});
      // The bootstrap wipes catalog metadata when the device timezone offset
      // moved; pin it so the metadata this test seeds survives.
      settings.catalogTimeZoneOffsetMillis = DateTime.now().timeZoneOffset.inMilliseconds;
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.loadedEntries.any((entry) => entry.id == 1 && entry.catalogMetadata != null));

      // The catalogued row reads exactly like a legacy in-memory row: tags,
      // rating, coordinates, catalogued mime and address are all there.
      final catalogued = lens.loadedEntries.firstWhere((entry) => entry.id == 1);
      expect(catalogued.rating, 4);
      expect(catalogued.tags, {'red', 'blue'});
      expect(catalogued.hasGps, isTrue);
      expect(catalogued.mimeType, 'image/heic');
      expect(catalogued.addressDetails?.locality, 'Paris');

      // ...and a row with no metadata row stays uncatalogued rather than wrong.
      final uncatalogued = lens.loadedEntries.firstWhere((entry) => entry.id == 2);
      expect(uncatalogued.catalogMetadata, isNull);
      expect(uncatalogued.addressDetails, isNull);
    });

    test('copying with other filters resolves that scope instead of serving this one', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2, dir: '/other')});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {StoredAlbumFilter('/album', null)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.entryCount == 1);
      expect(lens.sortedEntries.single.id, 1);

      // A named scope must be resolved like any other collection: serving it
      // from this lens's windows would silently show the wrong album.
      final scoped = lens.copyWith(filters: {StoredAlbumFilter('/other', null)});
      addTearDown(scoped.dispose);
      expect(scoped, isA<PagedCollectionLens>());
      expect(scoped, isNot(isA<PagedViewerCopy>()));
      expect(scoped.filters, {StoredAlbumFilter('/other', null)});
      final scopedLens = scoped as PagedCollectionLens;
      await settle(scopedLens, done: () => allReal(scopedLens) && scopedLens.entryCount == 1);
      expect(scopedLens.sortedEntries.single.id, 2);
    });

    test('trash scope pages with restore details', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2, trashed: true)});
      await service.updateTrash(2, const TrashDetails(id: 2, path: '/album/2.jpg', dateMillis: 7));
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {TrashFilter.instance});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.loadedEntries.length == 1);
      expect(lens.entryCount, 1);
      expect(lens.loadedEntries.single.trashDetails, isNotNull);
    });

    test('album scope pages one directory', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a/sub'), entry(3, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(source: source, filters: {StoredAlbumFilter('/a', null)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => allReal(lens) && lens.loadedEntries.length == 1);
      expect(lens.entryCount, 1);
      expect(lens.loadedEntries.single.id, 1);
    });

    test('paged enter drains the catalog backlog in the background', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(
        source: source,
        filters: {},
        catalogWorkerFactory: ({required source}) => PagedCatalogWorker(
          source: source,
          catalogEntry: (entry) async => entry.catalogMetadata = CatalogMetadata(id: entry.id, xmpSubjects: 't'),
        ),
      );
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 2 && lens.pagedActive);
      // the grid is instant; the backlog drains behind it
      for (var i = 0; i < 200; i++) {
        if (await service.countUncatalogued() == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(await service.countUncatalogued(), 0);
      expect((await service.loadCatalogMetadata()).length, 2);
    });

    test('reports and catalogues one album on demand from its header badge', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a'), entry(3, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final catalogued = <int>[];
      var catalog = false;
      var backlogStarted = false;
      PagedCatalogWorker? worker;
      final lens = PagedCollectionLens(
        source: source,
        filters: {},
        catalogWorkerFactory: ({required source}) => worker = PagedCatalogWorker(
          source: source,
          // The eager backlog is a no-op, so the badge keeps pending rows to
          // report; flipping the flag arms the on-demand pass.
          catalogEntry: (entry) async {
            backlogStarted = true;
            if (!catalog) return;
            catalogued.add(entry.id);
            entry.catalogMetadata = CatalogMetadata(id: entry.id);
          },
        ),
      );
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.albumUncatalogued('/a') == 2);
      // The eager backlog runs unawaited, and `catalogAlbum` is a no-op while the
      // worker is busy: hold the flag until that pass has started *and* finished,
      // or the two sweeps race over the same rows.
      await settle(lens, done: () => backlogStarted && worker?.isRunning == false);

      // The badge reads each album's own pending rows.
      expect(lens.albumUncatalogued('/a'), 2);
      expect(lens.albumUncatalogued('/b'), 1);
      expect(lens.albumUncatalogued('/missing'), 0);

      // A tap sweeps that album alone, leaving the rest of the library to the
      // backlog: only the rows of '/a' were catalogued.
      catalog = true;
      await lens.catalogAlbum('/a');
      expect(catalogued..sort(), [1, 2]);
      expect(await service.countUncatalogued(), 1);
    });

    test('a marked view declares its whole scope, not just the loaded rows', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 10);
      // Only the tail row is loaded: the mark must still cover the whole view.
      lens.sortedEntries[9];
      await settle(lens, done: () => lens.loadedEntries.any((entry) => entry.id == 1));

      final mark = lens.newSelectionMark()!;
      expect(mark.count, 10);

      final feed = lens.declaredFeed(mark)!;
      expect(feed.declared, isTrue);
      expect(feed.count, 10);
      final ids = <int>[];
      await for (final batch in feed.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {for (var i = 1; i <= 10; i++) i});
    });

    test('a declared feed still refuses to materialize past the limit', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 10);

      // Only a declared feed walks a scope into memory, so only it keeps the cap.
      final feed = lens.declaredFeed(lens.newSelectionMark()!)!;
      expect(await feed.materialize(limit: 10), hasLength(10));
      await expectLater(feed.materialize(limit: 9), throwsA(isA<EntryFeedTooLargeException>()));
    });

    test('a mark excludes the rows the user unmarked', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 10);

      final mark = lens.newSelectionMark()!;
      final unmarked = entry(1, dateTaken: 10);
      mark.unmark({unmarked});
      expect(mark.count, 9);

      final ids = <int>[];
      await for (final batch in lens.declaredFeed(mark)!.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {for (var i = 2; i <= 10; i++) i});
    });

    test('a section header turns into an exact trait over the whole album', () async {
      settings.setStoredCollectionSectionFactor({}, EntrySectionFactor.album);
      addTearDown(() => settings.setStoredCollectionSectionFactor({}, EntrySectionFactor.month));
      final service = await drift();
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a'), entry(3, dir: '/b'), entry(4, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 4);

      final mark = lens.newSelectionMark()!;
      final trait = lens.sectionTrait(const EntryAlbumSectionKey('/a'))!;
      mark.deselectTrait(trait, label: 'a');
      await mark.recount();

      // The trait covers the album, not the one row that happened to be loaded.
      expect(lens.sections[const EntryAlbumSectionKey('/a')]!.length, 2);
      expect(mark.count, 2);
      final ids = <int>[];
      await for (final batch in lens.declaredFeed(mark)!.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {3, 4});

      // Selecting it again wins over the op, restoring exactly those rows.
      mark.selectTrait(trait, label: 'a');
      await mark.recount();
      expect(mark.count, 4);
    });

    test('an album section with no directory has its own trait', () async {
      final service = await drift();
      final orphan = AvesEntry(
        id: 1,
        uri: 'content://1',
        path: null,
        contentId: 101,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: 5,
        sourceTitle: 'title1',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 0,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );
      await service.insertEntries({orphan, entry(2, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);

      final mark = lens.newSelectionMark()!;
      mark.deselectTrait(lens.sectionTrait(const EntryAlbumSectionKey(null))!, label: 'unknown');
      await mark.recount();
      expect(mark.count, 1);

      final ids = <int>[];
      await for (final batch in lens.declaredFeed(mark)!.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {2});
    });

    test('a rating section trait covers exactly the coalesced rating rows', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, rating: 4), CatalogMetadata(id: 2, rating: 4)});
      // The bootstrap wipes catalog metadata when the device timezone offset
      // moved; pin it so the metadata this test seeds survives.
      settings.catalogTimeZoneOffsetMillis = DateTime.now().timeZoneOffset.inMilliseconds;
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 3);

      final mark = lens.newSelectionMark()!;
      mark.deselectTrait(lens.sectionTrait(const EntryRatingSectionKey(4))!, label: 'four');
      await mark.recount();
      expect(mark.count, 1);

      final ids = <int>[];
      await for (final batch in lens.declaredFeed(mark)!.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {3});
    });

    test('a date section trait covers the local month its section groups', () async {
      final service = await drift();
      await service.insertEntries({
        entry(1, dateTaken: millis(2024, 1)),
        entry(2, dateTaken: millis(2024, 2)),
        entry(3, dateTaken: millis(2023, 1)),
      });
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 3);

      const sectionKey = EntryDateSectionKey(year: 2024, month: 1);
      final mark = lens.newSelectionMark()!;
      mark.deselectTrait(lens.sectionTrait(sectionKey)!, label: '2024-01');
      await mark.recount();

      // The trait covers the same rows the section shows, no more and no less.
      expect(lens.sections[sectionKey]!.length, 1);
      expect(mark.count, 2);
      final ids = <int>[];
      await for (final batch in lens.declaredFeed(mark)!.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {2, 3});
    });

    test('a section kind with no exact trait answers null', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);

      expect(lens.sectionTrait(const SectionKey()), isNull);
      expect(lens.sectionTrait(const EntryDateSectionKey()), isNull);
    });

    test('a feed walks a frozen scope: a row added later is not swept in', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 6; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 6);

      final feed = lens.declaredFeed(lens.newSelectionMark()!)!;
      expect(feed.count, 6);

      // The row matches the same mark, but it arrived after the action started:
      // the walk stops where the scope did.
      await service.insertEntries({entry(7, dateTaken: 70)});

      final ids = <int>[];
      await for (final batch in feed.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {for (var i = 1; i <= 6; i++) i});
    });

    test('a whole-view feed covers the view, not the loaded neighbourhood', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 10);

      // Nothing is unmarked: "empty the bin" targets the scope itself.
      final feed = lens.wholeViewFeed()!;
      expect(feed.declared, isTrue);
      expect(feed.count, 10);
      expect(feed.contains(entry(1)), isTrue);
    });

    test('the view reload is deferred while a run is active', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 6; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 6);

      final run = EntryFeedRun(lens.wholeViewFeed()!);
      await EntryFeedRun.install(run, () async {
        // A batch changing the source would reload the view; the run takes that
        // over so it happens once, when the action ends.
        lens.refresh();
        await pumpEventQueue();
      });

      expect(run.needsViewRefresh, isTrue);
    });

    test('the calendar layout declares a whole-view selection of its entries', () async {
      settings.setStoredCollectionTileLayout({}, TileLayout.calendar);
      addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
      final service = await drift();
      // Five entries on one day, five on the next.
      await service.insertEntries({for (var i = 1; i <= 10; i++) entry(i, dateTaken: i <= 5 ? 1000 : 1000 + 86400000)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);

      final mark = lens.newSelectionMark()!;
      // The view shows two days; the selection covers their ten entries, so the
      // app bar compares days while an action reports entries.
      expect(mark.count, 2);
      expect(mark.expandedCount, 10);

      final feed = lens.declaredFeed(mark)!;
      expect(feed.count, 10);
      final ids = <int>[];
      await for (final batch in feed.batches()) {
        ids.addAll(batch.map((entry) => entry.id));
      }
      expect(ids.toSet(), {for (var i = 1; i <= 10; i++) i});
    });

    test('a layout change during a resolve is applied after it', () async {
      final service = await drift();
      // Two days: the calendar projection totals 2 against 4 rows, so the count
      // says which layout the final window was resolved for.
      await service.insertEntries({
        for (var i = 1; i <= 4; i++) entry(i, dateTaken: i <= 2 ? millis(2024, 1) : millis(2024, 3, 5)),
      });
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 4);

      // Both changes land in the same turn: the first starts a resolve and the
      // second used to be dropped, leaving the calendar's day rows (total 2)
      // painted under the mosaic layout, without a ratio channel.
      settings.setStoredCollectionTileLayout({}, TileLayout.calendar);
      settings.setStoredCollectionTileLayout({}, TileLayout.mosaic);

      await settle(
        lens,
        done: () => lens.pagedActive && lens.entryCount == 4 && lens.mosaicRatios(const EntryDateSectionKey(year: 2024, month: 3)) != null,
      );
      expect(lens.entryCount, 4, reason: 'the last layout must win, not the calendar day count');
      // The grid follows the published window: it keeps the previous layout on
      // screen until the new one resolves, then switches with it.
      expect(lens.resolvedLayout, TileLayout.mosaic);
    });

    test('places backlog runs lazily when locations load', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: millis(2024, 1)), entry(2, dateTaken: millis(2024, 3))});
      await collectionPagingPrefs.setLargeThreshold(2);
      await collectionPagingPrefs.setWindowSize(10);
      final locatedIds = <int>[];
      late PagedCatalogWorker worker;
      final lens = PagedCollectionLens(
        source: source,
        filters: {},
        catalogWorkerFactory: ({required source}) => worker = PagedCatalogWorker(
          source: source,
          // id 1 is geotagged; bootstrap may wipe metadata, so the fake
          // catalog re-supplies the coordinates.
          catalogEntry: (entry) async => entry.catalogMetadata = CatalogMetadata(
            id: entry.id,
            latitude: entry.id == 1 ? 48.8 : null,
            longitude: entry.id == 1 ? 2.3 : null,
          ),
          locateCountry: (entry) async => AddressDetails(id: entry.id, countryCode: 'FR', countryName: 'FRA'),
          locatePlaces: (entry) async {
            locatedIds.add(entry.id);
            return AddressDetails(id: entry.id, countryCode: 'FR', countryName: 'France', adminArea: 'IDF', locality: 'Paris');
          },
          canLocate: () async => true,
        ),
      );
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 2 && lens.pagedActive);
      // Eager passes (catalog + countries) run on enter, places do not. The lens
      // starts them unawaited, so the test joins the drain instead of polling
      // the database, which would race the worker's own cooperative yields.
      unawaited(worker.run());
      await worker.whenIdle();
      expect(locatedIds, isEmpty);
      // opening a places surface loads the locations domain, which lazily
      // triggers the fine-places pass for the country-only row (id 1; id 2
      // has no gps)
      source.eventBus.fire(PlacesChangedEvent());
      await settle(lens, done: () => locatedIds.isNotEmpty);
      // The worker persists the located address once the fake returns, which is a
      // beat after the call the settle above observes: wait for the row itself
      // instead of racing it.
      for (var i = 0; i < 200; i++) {
        if ((await service.loadAddresses()).any((address) => address.locality == 'Paris')) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(locatedIds, [1]);
      expect((await service.loadAddresses()).single.locality, 'Paris');
    });

    test('resolves an entry index without loading a window', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 5; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setWindowSize(2);
      await collectionPagingPrefs.setLargeThreshold(2);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 5 && lens.pagedActive);

      // date desc: 5, 4, 3, 2, 1 — resolved straight from the database
      expect(await lens.indexOfId(5), 0);
      expect(await lens.indexOfId(1), 4);
      expect(await lens.indexOfId(999), -1);

      // the position agrees with the lazy window list once it fills
      await lens.fillAround(4);
      await settle(lens, done: () => lens.sortedEntries[4] is! SkeletonEntry);
      expect(lens.sortedEntries[4].id, 1);
    });

    test('resolves the legacy index in memory', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dateTaken: 10), entry(2, dateTaken: 20)});
      await collectionPagingPrefs.setLargeThreshold(100000);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 2);
      expect(lens.pagedActive, isFalse);
      expect(await lens.indexOfId(2), 0);
      expect(await lens.indexOfId(999), -1);
    });

    test('summaries outlive the lens for the top-level filter pages', () async {
      final service = await drift();
      await service.insertEntries({
        entry(1, dir: '/a', dateTaken: millis(2024, 3)),
        entry(2, dir: '/a', dateTaken: millis(2024, 1)),
      });
      // Force the windowed path: a small library would materialize instead.
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      await settle(lens, done: () => lens.entryCount == 2);
      expect(lens.pagedActive, isTrue);
      expect(source.summaries, isNotNull);

      // The album/tag/place pages are pushed with `pushAndRemoveUntil`, which
      // disposes the collection. Their counts must survive it.
      lens.dispose();
      expect(source.summaries, isNotNull);
      expect(source.count(StoredAlbumFilter('/a', null)), 2);
      forgetPagedSummaries(source);
    });

    test('a legacy view detaches the provider from the source', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(100000);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.entryCount == 2);
      expect(lens.pagedActive, isFalse);
      // Entries are materialized, so the source must answer from memory again.
      expect(source.summaries, isNull);
      forgetPagedSummaries(source);
    });

    test('a projection change reports a pending layout until it publishes', () async {
      final service = await drift();
      await service.insertEntries({
        for (var i = 1; i <= 4; i++) entry(i, dateTaken: i <= 2 ? millis(2024, 1) : millis(2024, 3, 5)),
      });
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(2);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 4);

      // Same projection (grid to mosaic): the window is reused, nothing to wait
      // for, and the grid repaints at once.
      settings.setStoredCollectionTileLayout({}, TileLayout.mosaic);
      expect(lens.layoutPending, isFalse);
      await settle(lens, done: () => lens.resolvedLayout == TileLayout.mosaic);

      // To the calendar: a different projection, so the body waits for the new
      // window instead of painting day rows as a grid.
      settings.setStoredCollectionTileLayout({}, TileLayout.calendar);
      expect(lens.layoutPending, isTrue);
      await settle(lens, done: () => !lens.layoutPending);
      expect(lens.resolvedLayout, TileLayout.calendar);
      expect(lens.entryCount, 2);

      // And back out of the calendar.
      settings.setStoredCollectionTileLayout({}, TileLayout.list);
      expect(lens.layoutPending, isTrue);
      await settle(lens, done: () => !lens.layoutPending);
      expect(lens.resolvedLayout, TileLayout.list);
      expect(lens.entryCount, 4);
      expect(lens.loadedEntries, isNotEmpty, reason: 'the first window is prefetched before publishing');
    });

    test('a view that announced loading hands it back when it is parked', () async {
      final service = await drift();
      await service.insertEntries({for (var i = 1; i <= 200; i++) entry(i)});
      await collectionPagingPrefs.setLargeThreshold(1);

      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      // The resolve reports its steps through the lens, so parking can land while
      // it is still reading. The announcement must not outlive the view that made
      // it, or the whole app would read "loading" with nothing left to clear it.
      var parked = false;
      SourceState? stateWhileResolving;
      SourceState? stateAfterParking;
      void onStep() {
        if (parked || lens.resolvePhase == null) return;
        parked = true;
        stateWhileResolving = source.state;
        lens.setActive(false);
        stateAfterParking = source.state;
      }

      lens.addListener(onStep);
      addTearDown(() => lens.removeListener(onStep));

      await settle(lens, done: () => lens.pagedActive);
      expect(parked, isTrue, reason: 'the resolve reported a step before publishing');
      expect(stateWhileResolving, SourceState.loading, reason: 'the first resolve says it is resolving');
      expect(stateAfterParking, isNot(SourceState.loading), reason: 'parking hands the loading back');
      expect(lens.entryCount, 200);
    });

    test('a pass superseded by a layout switch does not leave the view on its own loading', () async {
      final service = await drift();
      await service.insertEntries({
        for (var i = 1; i <= 200; i++) entry(i, dateTaken: i <= 100 ? millis(2024, 1) : millis(2024, 2)),
      });
      // Everything catalogued: no worker runs alongside the resolve, so nothing
      // else clears the loading this lens announced. That is the state the guard
      // is about, and a sweep would mask it.
      await service.saveCatalogMetadata({for (var i = 1; i <= 200; i++) CatalogMetadata(id: i)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(20);
      addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));

      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      // The pass captures the layout and then reports its count: switching the
      // layout from that notification makes it end without publishing, which is
      // the exit that must not leave the shared state terminal. The pass that
      // follows must resolve instead of waiting for the loading this lens
      // announced.
      var switched = false;
      SourceState? stateWhileResolving;
      void onStep() {
        if (switched || lens.resolvePhase != PagedResolvePhase.counting) return;
        switched = true;
        stateWhileResolving = source.state;
        settings.setStoredCollectionTileLayout({}, TileLayout.list);
        // Coalesce into the running pass: the switch alone is picked up by the
        // settings notification, which lands after this pass has already ended.
        lens.refresh(dataChanged: false);
      }

      lens.addListener(onStep);
      addTearDown(() => lens.removeListener(onStep));

      await settle(lens, done: () => lens.pagedActive && lens.resolvedLayout == TileLayout.list);
      expect(switched, isTrue, reason: 'the pass reported its count before publishing');
      expect(stateWhileResolving, SourceState.loading);
      expect(lens.entryCount, 200);
      expect(source.state, isNot(SourceState.loading));
      expect(lens.resolvePhase, isNull);
    });

    test('a layout switch over the same rows keeps the loaded window', () async {
      final service = await drift();
      await service.insertEntries({
        for (var i = 1; i <= 4; i++) entry(i, dateTaken: i <= 2 ? millis(2024, 1) : millis(2024, 3)),
      });
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(2);
      final lens = PagedCollectionLens(
        source: source,
        filters: {},
        catalogWorkerFactory: ({required source}) => PagedCatalogWorker(
          source: source,
          catalogEntry: (entry) async => entry.catalogMetadata = CatalogMetadata(id: entry.id, xmpSubjects: 'sweep'),
        ),
      );
      addTearDown(lens.dispose);
      addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
      await settle(lens, done: () => lens.pagedActive && allReal(lens));
      // The eager sweep reloads the view once when it ends; start from after it.
      for (var i = 0; i < 200; i++) {
        if (await service.countUncatalogued() == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle(lens, done: () => lens.pagedActive && allReal(lens));

      final sections = lens.sections;
      final loaded = lens.loadedEntries.map((e) => e.id).toSet();
      expect(loaded, isNotEmpty);

      // The same rows in the same order, only the presentation changes: the
      // window and its loaded rows must survive, or every tile falls back to a
      // skeleton for the length of a full refetch.
      settings.setStoredCollectionTileLayout({}, TileLayout.mosaic);
      await settle(lens, done: () => lens.resolvedLayout == TileLayout.mosaic);

      expect(identical(lens.sections, sections), isTrue, reason: 'a layout switch must not rebuild the window');
      expect(lens.loadedEntries.map((e) => e.id).toSet(), loaded);
      expect(allReal(lens), isTrue, reason: 'no tile may fall back to a skeleton');
      expect(lens.mosaicRatios(lens.sections.keys.first), isNotNull, reason: 'the mosaic channel is measured before switching');
    });

    test('cataloguing patches the mounted tiles instead of rebuilding the window', () async {
      final service = await drift();
      await service.insertEntries({
        entry(1, dir: '/a', dateTaken: millis(2024, 3)),
        entry(2, dir: '/a', dateTaken: millis(2024, 1)),
      });
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      final lens = PagedCollectionLens(
        source: source,
        filters: {},
        catalogWorkerFactory: ({required source}) => PagedCatalogWorker(
          source: source,
          catalogEntry: (entry) async => entry.catalogMetadata = CatalogMetadata(id: entry.id, xmpSubjects: 'sweep'),
        ),
      );
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && allReal(lens));
      // The eager sweep settles the view once when it ends. Capture the window
      // after that, so the assertions below are about the catalog event alone.
      for (var i = 0; i < 200; i++) {
        if (await service.countUncatalogued() == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await settle(lens, done: () => lens.pagedActive && allReal(lens));

      final sections = lens.sections;

      // A pass persists a batch and announces it, exactly like the worker does.
      await service.saveCatalogMetadata({CatalogMetadata(id: 1, xmpSubjects: 'batch')});
      source.eventBus.fire(CatalogMetadataChangedEvent());
      // The patch is coalesced, so it lands a beat after the event.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(identical(lens.sections, sections), isTrue, reason: 'a catalog event must not rebuild the sections');
      expect(allReal(lens), isTrue, reason: 'no tile may fall back to a skeleton');
      expect(lens.sortedEntries.firstWhere((e) => e.id == 1).catalogMetadata?.xmpSubjects, 'batch');
      expect(source.state, SourceState.ready);
    });

    test('a first resolve settles out of loading', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setAskBeforeCatalog(true);
      addTearDown(() => collectionPagingPrefs.setAskBeforeCatalog(false));
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);
      // A catalog pass may legitimately own the state by now; what must never
      // happen is a resolved window that still reads as loading.
      expect(source.state, isNot(SourceState.loading), reason: 'a resolved window must not read as loading');
    });

    test('a refresh does not overwrite the catalog pass state', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(1);
      await collectionPagingPrefs.setWindowSize(10);
      // Held back, so no pass runs behind the assertion.
      await collectionPagingPrefs.setAskBeforeCatalog(true);
      addTearDown(() => collectionPagingPrefs.setAskBeforeCatalog(false));
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && allReal(lens));

      // The app bar shows the pass's own clock while it runs; a reload used to
      // write `ready` back, flipping the subtitle on every refresh.
      source.state = SourceState.cataloguing;
      lens.refresh();
      await settle(lens, done: () => lens.pagedActive && allReal(lens));
      expect(source.state, SourceState.cataloguing);
    });

    test('a lost preference does not re-import a complete database', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      // The marker is written next to the rows: preferences can be reset, the
      // database cannot without losing the library.
      await service.writeImportComplete();
      await collectionPagingPrefs.setImportComplete(false);
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);
      expect(collectionPagingPrefs.importComplete, isTrue);
      expect(pagedImportStatus.active, isFalse, reason: 'a complete library must not be scanned again');
    });

    test('emptying the filters widens the view in one refresh', () async {
      final service = await drift();
      await service.insertEntries({entry(1, dir: '/a'), entry(2, dir: '/a'), entry(3, dir: '/b')});
      await collectionPagingPrefs.setLargeThreshold(1);
      final lens = PagedCollectionLens(source: source, filters: {StoredAlbumFilter('/a', null)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);

      // What the filter row's clear action does: the scope's own chip goes too,
      // so the whole library is what is left.
      lens.setFilters({});
      await settle(lens, done: () => lens.entryCount == 3);
      expect(lens.filters, isEmpty);
      expect(lens.pagedActive, isTrue);
    });

    test('a parked view neither drives the state nor resolves; adopting it does', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      await collectionPagingPrefs.setLargeThreshold(1);

      // A retained scope: its resolve is held back, or the page on screen would
      // flip to "loading" for rows nobody is looking at.
      final parked = PagedCollectionLens(source: source, filters: {});
      addTearDown(parked.dispose);
      parked.setActive(false);
      await parked.ready;
      expect(parked.pagedActive, isTrue);
      expect(source.state, isNot(SourceState.loading));

      // A change while parked is owed, not read behind the scenes.
      parked.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(parked.loadedEntries, isNotEmpty, reason: 'the published window is kept, not rebuilt');

      // A page adopting a lens whose window has not landed learns it from the
      // lens, not from the shared state, and the resolve still finishes.
      final adopted = PagedCollectionLens(source: source, filters: {});
      addTearDown(adopted.dispose);
      adopted.setActive(false);
      adopted.setActive(true);
      expect(adopted.awaitingFirstWindow, isTrue, reason: 'the page paints a loading body from this');
      await settle(adopted, done: () => adopted.pagedActive && adopted.entryCount == 2);
      expect(adopted.awaitingFirstWindow, isFalse);
      expect(source.state, isNot(SourceState.loading));
    });

    test('a settled library resolves on the first visit instead of waiting on itself', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2)});
      // Everything catalogued: no worker runs alongside the resolve, so nothing
      // else touches the shared state. This is a library that has been used for a
      // while, and activation used to announce `loading` before the resolve's own
      // in-flight check, which then waited for that very resolve: a deadlock.
      await service.saveCatalogMetadata({CatalogMetadata(id: 1), CatalogMetadata(id: 2)});
      await collectionPagingPrefs.setLargeThreshold(1);

      final lens = PagedCollectionLens(source: source, filters: {});
      addTearDown(lens.dispose);
      lens.setActive(false);
      lens.setActive(true);
      await settle(lens, done: () => lens.pagedActive && lens.entryCount == 2);
      expect(source.state, isNot(SourceState.loading), reason: 'a resolved view must not read as loading');
    });
  });
}

/// A source standing in for the home page's first load: the library is loading
/// and no scope is reported until [completeLoad] lands its entries.
class _LoadingSource extends MediaStoreSource {
  var initCount = 0;
  var _loaded = false;

  @override
  SourceScope get loadedScope => _loaded ? CollectionSource.fullScope : null;

  Future<void> completeLoad(Set<AvesEntry> entries) async {
    // Mirrors the essentials a real load completes before it adds entries.
    await loadDates();
    addEntries(entries);
    _loaded = true;
    // Leaving `loading` is what the lens waits for; the analysis that follows in
    // a real load is not waited for.
    state = SourceState.ready;
  }

  @override
  Future<void> init({required SourceScope scope, AnalysisController? analysisController, bool loadTopEntriesFirst = false}) async {
    initCount++;
    _loaded = true;
  }
}
