import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/query/shuffle_permutation.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Viewer copies over a paged collection: live index resolution through the
/// parent's windows, bounded video search, and inert lifecycle.
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
    await collectionPagingPrefs.setEngine(CollectionEngine.auto);
    await collectionPagingPrefs.setWindowSize(2);
    await collectionPagingPrefs.setPrefetchScreens(0);
    await collectionPagingPrefs.setLargeThreshold(2);
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
    int dateTaken = 0,
    bool video = false,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: video ? 'video/mp4' : 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: video ? 1000 : 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int day) => DateTime.utc(2024, 1, day).millisecondsSinceEpoch;

  Future<PagedCollectionLens> settleLens(Set<AvesEntry> entries) async {
    await driftDb.insertEntries(entries);
    final lens = PagedCollectionLens(source: source, filters: {});
    addTearDown(lens.dispose);
    for (var i = 0; i < 200; i++) {
      if (lens.entryCount == entries.length && lens.pagedActive) return lens;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('paged lens did not settle');
  }

  Future<PagedCollectionLens> pagedLens(int count) => settleLens({for (var i = 1; i <= count; i++) entry(i, dateTaken: millis(i))});

  group('PagedViewerCopy', () {
    test('resolves entries by global index across windows', () async {
      final lens = await pagedLens(5);
      final copy = lens.copyWith(listenToSource: false);
      expect(copy, isA<PagedViewerCopy>());
      addTearDown(copy.dispose);
      final viewer = copy as PagedViewerCopy;

      expect(viewer.entryCount, 5);
      expect(viewer.sortedEntries.length, 5);
      // untouched positions are skeletons that kick their window
      expect(viewer.entryAt(4), isA<SkeletonEntry>());
      // ...and fill in display order (date desc: id 5 first)
      for (var i = 0; i < 200; i++) {
        if (viewer.entryAt(4) is! SkeletonEntry && viewer.entryAt(0) is! SkeletonEntry) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(viewer.entryAt(4).id, 1);
      expect(viewer.entryAt(0).id, 5);
    });

    test('tracks the tapped entry and prefetches around it', () async {
      final lens = await pagedLens(5);
      // settle the first window like the grid would
      for (var i = 0; i < 200; i++) {
        if (lens.sortedEntries[0] is! SkeletonEntry) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final tapped = lens.sortedEntries[0];
      expect(tapped.id, 5);
      final viewer = lens.copyWith(listenToSource: false) as PagedViewerCopy;
      addTearDown(viewer.dispose);

      expect(viewer.globalIndexOf(tapped), 0);
      await viewer.prefetchAround(4);
      for (var i = 0; i < 200; i++) {
        if (viewer.entryAt(4) is! SkeletonEntry) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(viewer.entryAt(4), isNot(SkeletonEntry));
    });

    test('finds neighbor videos with a bounded scan', () async {
      final lens = await settleLens({for (var i = 1; i <= 5; i++) entry(i, dateTaken: millis(i)), entry(6, dateTaken: millis(6), video: true)});
      final viewer = lens.copyWith(listenToSource: false) as PagedViewerCopy;
      addTearDown(viewer.dispose);
      expect(viewer.entryCount, 6);

      // video is the most recent (index 0); from index 3 forward is index 2..0
      expect(await viewer.findNeighborVideo(3, -1), 0);
      expect(await viewer.findNeighborVideo(3, 1, maxSteps: 2), isNull);
      expect(await viewer.findNeighborVideo(0, -1), isNull);
      expect(await viewer.findNeighborVideo(5, 1), isNull);
    });

    test('reports the outward video neighbours in both directions', () async {
      final lens = await settleLens({
        for (var i = 1; i <= 5; i++) entry(i, dateTaken: millis(i)),
        entry(6, dateTaken: millis(6), video: true),
        entry(7, dateTaken: millis(7), video: true),
      });
      final viewer = lens.copyWith(listenToSource: false) as PagedViewerCopy;
      addTearDown(viewer.dispose);
      // display order is date desc: 7, 6 (videos) then 5..1
      expect(viewer.entryCount, 7);

      // the newest video: the other video is next, nothing before it
      expect(await viewer.neighborVideos(0), (previous: false, next: true));
      // the older video: the newer one is before it, the images are after
      expect(await viewer.neighborVideos(1), (previous: true, next: false));
      // an image in the middle: both videos are newer, no video older
      expect(await viewer.neighborVideos(3), (previous: true, next: false));
      // the oldest image: the videos are behind it, nothing ahead
      expect(await viewer.neighborVideos(6), (previous: true, next: false));
    });

    test('does not own entries or outlive its parent', () async {
      // explicit lifecycle (no addTearDown): this test disposes on purpose
      await driftDb.insertEntries({for (var i = 1; i <= 3; i++) entry(i, dateTaken: millis(i))});
      final lens = PagedCollectionLens(source: source, filters: {});
      for (var i = 0; i < 200; i++) {
        if (lens.entryCount == 3 && lens.pagedActive) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(lens.pagedActive, isTrue);

      final viewer = lens.copyWith(listenToSource: false) as PagedViewerCopy;
      // disposing the copy leaves the parent usable and entries undisposed
      viewer.dispose();
      expect(lens.entryCount, 3);
      expect(lens.sortedEntries.whereType<SkeletonEntry>(), isNotEmpty);

      final viewer2 = lens.copyWith(listenToSource: false) as PagedViewerCopy;
      lens.dispose();
      expect(viewer2.entryCount, 0);
      expect(viewer2.sortedEntries, isEmpty);
      viewer2.dispose();
    });
  });

  group('PagedViewerCopy with a shuffle seed', () {
    test('indexes the shuffled order and stays inverse to globalIndexOf', () async {
      const seed = 42;
      final lens = await pagedLens(5);
      final shuffled = PagedViewerCopy(parent: lens, shuffleSeed: seed);
      addTearDown(shuffled.dispose);

      // load every position (scattered across the parent's windows)
      for (var i = 0; i < 5; i++) {
        await shuffled.prefetchAround(i);
      }
      final sequentialIds = [for (var i = 0; i < 5; i++) lens.sortedEntries[i].id];
      final permutation = ShufflePermutation(seed, 5);
      final shuffledIds = [for (var i = 0; i < 5; i++) shuffled.entryAt(i).id];

      // a true permutation, in the seeded order
      expect(shuffledIds, [for (var v = 0; v < 5; v++) sequentialIds[permutation.forward(v)]]);
      expect(shuffledIds.toSet(), sequentialIds.toSet());
      // entryAt/globalIndexOf are inverse, and sortedEntries is the virtual list
      for (var v = 0; v < 5; v++) {
        expect(shuffled.globalIndexOf(shuffled.entryAt(v)), v);
        expect(shuffled.sortedEntries[v].id, shuffled.entryAt(v).id);
      }
      expect(shuffled.sortedEntries.indexOf(shuffled.entryAt(3)), 3);
    });

    test('a null seed keeps the collection order', () async {
      final lens = await pagedLens(4);
      final sequential = PagedViewerCopy(parent: lens);
      addTearDown(sequential.dispose);
      for (var i = 0; i < 4; i++) {
        await sequential.prefetchAround(i);
      }
      expect([for (var i = 0; i < 4; i++) sequential.entryAt(i).id], [for (var i = 0; i < 4; i++) lens.sortedEntries[i].id]);
      expect(sequential.sortedEntries, same(lens.sortedEntries));
    });
  });
}
