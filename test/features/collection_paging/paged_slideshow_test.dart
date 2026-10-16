import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/view/paged_slideshow.dart';
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

/// The paged slideshow/screen-saver session: a window-backed shuffled playlist
/// over a paged collection, or null so the caller keeps the legacy snapshot.
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
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    await setUpServices();
  });

  AvesEntry entry(int id, {int dateTaken = 0, bool video = false}) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '/album/$id.jpg',
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

  group('PagedSlideshow', () {
    test('opens a shuffled window-backed playlist over a paged scope', () async {
      await driftDb.insertEntries({for (var i = 1; i <= 5; i++) entry(i, dateTaken: i * 10)});
      final session = await PagedSlideshow.open(source: source, filters: {}, skipVideos: false, seed: 42);
      expect(session, isNotNull);
      addTearDown(session!.dispose);

      final view = session.collection;
      expect(view.entryCount, 5);
      expect(view.shuffleSeed, 42);
      // the first position resolves to a real entry (not a skeleton)
      await session.ready();
      expect(view.entryAt(0), isNot(isA<SkeletonEntry>()));
      expect(view.sortedEntries.first, isNot(isA<SkeletonEntry>()));

      // walking every position yields the whole collection exactly once
      for (var v = 0; v < 5; v++) {
        await view.prefetchAround(v);
      }
      expect({for (var v = 0; v < 5; v++) view.entryAt(v).id}, {1, 2, 3, 4, 5});
    });

    test('skipVideos excludes videos from the total and the order', () async {
      await driftDb.insertEntries({entry(1, dateTaken: 10), entry(2, dateTaken: 20, video: true), entry(3, dateTaken: 30)});
      final session = await PagedSlideshow.open(source: source, filters: {}, skipVideos: true, seed: 42);
      expect(session, isNotNull);
      addTearDown(session!.dispose);

      expect(session.collection.entryCount, 2);
      await session.ready();
      final ids = <int>{};
      for (var v = 0; v < 2; v++) {
        await session.collection.prefetchAround(v);
        ids.add(session.collection.entryAt(v).id);
      }
      expect(ids, {1, 3});
    });

    test('keeps the legacy path below the threshold', () async {
      await driftDb.insertEntries({entry(1)});
      await collectionPagingPrefs.setLargeThreshold(100);
      expect(await PagedSlideshow.open(source: source, filters: {}, skipVideos: false), isNull);
    });

    test('keeps the legacy path when the engine is legacy', () async {
      await driftDb.insertEntries({for (var i = 1; i <= 5; i++) entry(i, dateTaken: i * 10)});
      await collectionPagingPrefs.setEngine(CollectionEngine.legacy);
      expect(await PagedSlideshow.open(source: source, filters: {}, skipVideos: false), isNull);
    });
  });
}
