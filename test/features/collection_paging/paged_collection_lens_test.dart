import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/paged_viewer_copy.dart';
import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Paged lens behaviour against an in-memory Drift database: auto morphing,
/// windowed reads with skeletons, blocking, and viewer copies.
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
    await collectionPagingPrefs.setWindowSize(200);
    await collectionPagingPrefs.setPrefetchScreens(0);
    await collectionPagingPrefs.setLargeThreshold(100000);
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
    fail('paged lens did not settle (entryCount=${lens.entryCount}, blocked=${lens.pagedBlocked})');
  }

  /// Reads every row, kicking off fetches like the sliver would, until none
  /// are skeletons. Non-empty is required: `every` is vacuously true on an
  /// empty list.
  bool allReal(PagedCollectionLens lens) => lens.sortedEntries.isNotEmpty && lens.sortedEntries.every((e) => e is! SkeletonEntry);

  Future<DriftLocalMediaDb> drift() async => getIt<LocalMediaDb>() as DriftLocalMediaDb;

  group('PagedCollectionLens', () {
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

    test('unsupported filters block instead of crashing', () async {
      final service = await drift();
      await service.insertEntries({entry(1), entry(2), entry(3)});
      await collectionPagingPrefs.setLargeThreshold(2);
      final lens = PagedCollectionLens(source: source, filters: {QueryFilter('a', ACalendar.gregorian, live: true)});
      addTearDown(lens.dispose);
      await settle(lens, done: () => lens.pagedBlocked);
      expect(lens.entryCount, 0);
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
  });
}
