import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../fake/db.dart';
import '../../helpers/sqlite3_loader.dart';

/// Routing between the legacy full load and the paged path.
void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late AppDatabase db;
  late DriftLocalMediaDb driftDb;

  setUp(() async {
    await collectionPagingPrefs.init();
    db = AppDatabase(NativeDatabase.memory());
    driftDb = DriftLocalMediaDb(database: db);
    await driftDb.init();
  });

  tearDown(() async {
    await db.close();
    await setUpServices();
  });

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
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  Future<void> configure({required CollectionEngine engine, required int threshold}) async {
    await collectionPagingPrefs.setEngine(engine);
    await collectionPagingPrefs.setLargeThreshold(threshold);
  }

  const router = CollectionEngineRouter();

  group('CollectionEngineRouter', () {
    test('explicit legacy always wins, even above threshold', () async {
      await driftDb.insertEntries({for (var id = 1; id <= 10; id++) entry(id)});
      await configure(engine: CollectionEngine.legacy, threshold: 5);
      final decision = await router.resolve(filters: {}, database: driftDb);
      expect(decision.route, CollectionRoute.legacy);
    });

    test('unsupported filters keep the legacy path', () async {
      await configure(engine: CollectionEngine.paged, threshold: 5);
      final decision = await router.resolve(
        // A `/regex/` title match has no SQL translation.
        filters: {QueryFilter(r'/holiday/', ACalendar.gregorian)},
        database: driftDb,
      );
      expect(decision.route, CollectionRoute.legacy);
      expect(decision.reason, isNotNull);
    });

    test('auto pages at or above the threshold', () async {
      await driftDb.insertEntries({for (var id = 1; id <= 10; id++) entry(id)});
      await configure(engine: CollectionEngine.auto, threshold: 10);
      final decision = await router.resolve(filters: {}, database: driftDb);
      expect(decision.route, CollectionRoute.paged);
      expect(decision.total, 10);
      expect(decision.predicate, isNotNull);
    });

    test('auto keeps legacy below the threshold', () async {
      await driftDb.insertEntries({for (var id = 1; id <= 10; id++) entry(id)});
      await configure(engine: CollectionEngine.auto, threshold: 11);
      final decision = await router.resolve(filters: {}, database: driftDb);
      expect(decision.route, CollectionRoute.legacy);
    });

    test('explicit paged forces the path on small collections', () async {
      await driftDb.insertEntries({entry(1)});
      await configure(engine: CollectionEngine.paged, threshold: 100000);
      final decision = await router.resolve(filters: {}, database: driftDb);
      expect(decision.route, CollectionRoute.paged);
      expect(decision.total, 1);
    });

    test('hidden filters are compiled into the predicate', () async {
      await driftDb.insertEntries({entry(1)});
      await configure(engine: CollectionEngine.paged, threshold: 1);
      final old = settings.hiddenFilters;
      try {
        settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
        final decision = await router.resolve(filters: {}, database: driftDb);
        expect(decision.route, CollectionRoute.paged);
        // The hidden album is not the entry's album, so it still shows.
        expect(decision.total, 1);
      } finally {
        settings.hiddenFilters = old;
      }
    });

    test('a failed probe keeps the legacy path', () async {
      await configure(engine: CollectionEngine.paged, threshold: 1);
      final decision = await router.resolve(filters: {}, database: _FailingDb());
      expect(decision.route, CollectionRoute.legacy);
      expect(decision.reason, isNotNull);
    });
  });
}

class _FailingDb extends FakeAvesDb {
  @override
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) => throw StateError('no database');
}
