import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/type.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// Stacks in the paged view: a group shows one tile carrying its frames, and a
/// member whose tile is out of scope comes back instead of disappearing.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
    settings.collectionBurstPatterns = [BurstPatterns.samsung];
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
    // Force the paged path for a handful of entries.
    await collectionPagingPrefs.setLargeThreshold(1);
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

  AvesEntry entry(int id, {required String path, String mime = MimeTypes.jpeg, bool trashed = false, DateTime? taken, int width = 10, int height = 20}) => AvesEntry(
        id: id,
        uri: 'content://$id',
        path: path,
        contentId: 100 + id,
        pageId: null,
        sourceMimeType: mime,
        width: width,
        height: height,
        sourceRotationDegrees: 0,
        sizeBytes: 5,
        sourceTitle: 'title$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: taken?.millisecondsSinceEpoch ?? 0,
        durationMillis: 0,
        trashed: trashed,
        origin: EntryOrigins.mediaStoreContent,
      );

  /// The visible tiles: unloaded positions hold skeletons (`id == -1`).
  Set<int> tilesOf(PagedCollectionLens lens) => {
        for (final entry in lens.loadedEntries)
          if (entry.id > 0) entry.id,
      };

  Future<PagedCollectionLens> openLens(Set<CollectionFilter> filters) async {
    final lens = PagedCollectionLens(source: source, filters: filters);
    addTearDown(lens.dispose);
    await lens.ready;
    await lens.fillAround(0);
    // A reload can land between the fill request and its callback (the
    // background catalogue fires a metadata change right after the view
    // resolves) and a fill from a replaced cache is dropped. The layout keeps
    // asking for its windows, so the test does the same instead of reading a
    // half-filled view.
    for (var attempt = 0; attempt < 20 && lens.loadedEntries.isEmpty && lens.entryCount > 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await lens.fillAround(0);
    }
    return lens;
  }

  /// Waits for a fire-and-forget update (the stack members arrive after the
  /// window is on screen).
  Future<void> pumpUntil(bool Function() condition) async {
    for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  test('a burst shows one tile carrying its frames', () async {
    await driftDb.insertEntries({
      entry(1, path: '/cam/20151021_072800_001.jpg'),
      entry(2, path: '/cam/20151021_072800_002.jpg'),
      entry(3, path: '/cam/other.jpg'),
    });

    final lens = await openLens({});
    expect(tilesOf(lens), {1, 3});

    await pumpUntil(() => lens.loadedEntries.any((entry) => entry.id == 1 && entry.stackedEntries != null));
    final tile = lens.loadedEntries.firstWhere((entry) => entry.id == 1);
    expect(tile.stackedEntries?.map((entry) => entry.id).toList(), [1, 2]);
  });

  test('a raw sibling shows when its developed tile is filtered out', () async {
    await driftDb.insertEntries({
      entry(1, path: '/cam/20151021_072800_001.jpg'),
      entry(2, path: '/cam/IMG_1.jpg'),
      entry(3, path: '/cam/IMG_1.dng', mime: MimeTypes.dng),
    });

    // Unfiltered: the raw hides behind the developed image.
    expect(tilesOf(await openLens({})), {1, 2});

    // Filtering to raw types keeps the raw reachable instead of hiding it
    // behind a tile the view no longer contains.
    expect(tilesOf(await openLens({TypeFilter.raw})), {3});
  });

  test('a raw sibling shows when its developed tile is in the bin', () async {
    await driftDb.insertEntries({
      entry(1, path: '/cam/IMG_1.jpg', trashed: true),
      entry(2, path: '/cam/IMG_1.dng', mime: MimeTypes.dng),
    });

    // The live view has no tile for the pair, so the raw must show itself.
    expect(tilesOf(await openLens({})), {2});
  });

  test('the calendar layout shows one row per day', () async {
    settings.setStoredCollectionTileLayout({}, TileLayout.calendar);
    addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
    await driftDb.insertEntries({
      entry(1, path: '/cam/a.jpg', taken: DateTime(2024, 3, 5, 9)),
      entry(2, path: '/cam/b.jpg', taken: DateTime(2024, 3, 5, 20)),
      entry(3, path: '/cam/c.jpg', taken: DateTime(2024, 3, 7, 12)),
    });

    final lens = await openLens({});
    // Two days under one month section, and the day's second frame hides behind
    // its representative instead of showing as a tile of its own.
    expect(lens.sections.values.map((section) => section.length).toList(), [2]);
    expect(tilesOf(lens), {1, 3});

    await pumpUntil(() => lens.loadedEntries.any((entry) => entry.id == 1 && entry.stackedEntries != null));
    final day = lens.loadedEntries.firstWhere((entry) => entry.id == 1);
    expect(day.stackedEntries?.map((entry) => entry.id).toList(), [1, 2]);
  });

  test('the mosaic layout packs a section from its ratio channel', () async {
    settings.setStoredCollectionTileLayout({}, TileLayout.mosaic);
    addTearDown(() => settings.setStoredCollectionTileLayout({}, TileLayout.grid));
    await driftDb.insertEntries({
      entry(1, path: '/cam/a.jpg', taken: DateTime(2024, 3, 5), width: 400, height: 200),
      entry(2, path: '/cam/b.jpg', taken: DateTime(2024, 3, 4), width: 200, height: 400),
      entry(3, path: '/cam/c.jpg', taken: DateTime(2024, 3, 3), width: 300, height: 400),
    });

    final lens = await openLens({});
    // The mosaic shows the entries themselves, windowed like the grid.
    expect(tilesOf(lens), {1, 2, 3});

    // The engine measures the section without reading it: the ratios arrive in
    // collection order, for the layout to pack with.
    await pumpUntil(() => lens.sections.keys.every((key) => lens.mosaicRatios(key) != null));
    expect(lens.mosaicRatios(lens.sections.keys.single), [2.0, 0.5, 0.75]);
  });
}
