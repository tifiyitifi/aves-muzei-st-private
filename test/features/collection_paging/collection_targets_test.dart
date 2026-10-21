import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/view/collection_targets.dart';
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

/// Entry-set action targets on a windowed collection: the loaded rows, never a
/// walk of the lazy list.
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
    // One row per window, so "loaded" is clearly smaller than "everything".
    await collectionPagingPrefs.setWindowSize(1);
    await collectionPagingPrefs.setPrefetchScreens(0);
    await collectionPagingPrefs.setLargeThreshold(1);
    // The size rules assume a library that has been imported once: before that,
    // a full load is never provably safe (see `allowFullLoad`).
    await collectionPagingPrefs.setImportComplete(true);
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

  AvesEntry entry(int id) => AvesEntry(
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
        sourceDateTakenMillis: DateTime.utc(2024, 1, id).millisecondsSinceEpoch,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  Future<PagedCollectionLens> settleLens(int count) async {
    await driftDb.insertEntries({for (var i = 1; i <= count; i++) entry(i)});
    final lens = PagedCollectionLens(source: source, filters: {});
    addTearDown(lens.dispose);
    for (var i = 0; i < 200; i++) {
      if (lens.entryCount == count && lens.pagedActive) return lens;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('paged lens did not settle');
  }

  Future<void> settleLoaded(PagedCollectionLens lens) async {
    // The grid reads rows, which is what kicks a window in.
    lens.sortedEntries[0];
    for (var i = 0; i < 200; i++) {
      if (lens.loadedEntries.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('no window filled');
  }

  test('browsing targets the loaded rows, not a walk of the lazy list', () async {
    final lens = await settleLens(3);
    await settleLoaded(lens);

    final targets = collectionTargetItems(collection: lens, isSelecting: false, selectedItems: const {});
    expect(targets.map((entry) => entry.id), lens.loadedEntries.map((entry) => entry.id).toSet());
    // Bounded by the window, not by the collection.
    expect(targets.length, lessThan(lens.entryCount));
  });

  test('selecting targets the selection', () async {
    final lens = await settleLens(3);
    final selected = entry(2);

    final targets = collectionTargetItems(collection: lens, isSelecting: true, selectedItems: {selected});
    expect(targets, {selected});
  });

  test('an in-memory collection still targets every entry', () async {
    await collectionPagingPrefs.setLargeThreshold(100000);
    await driftDb.insertEntries({for (var i = 1; i <= 3; i++) entry(i)});
    final lens = PagedCollectionLens(source: source, filters: {});
    addTearDown(lens.dispose);
    // Below the threshold the lens morphs into the legacy one.
    for (var i = 0; i < 200; i++) {
      if (!lens.pagedActive && !lens.pagedBlocked && lens.entryCount == 3) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(lens.pagedActive, isFalse);
    expect(lens.pagedBlocked, isFalse);

    final targets = collectionTargetItems(collection: lens, isSelecting: false, selectedItems: const {});
    expect(targets.length, 3);
  });
}
