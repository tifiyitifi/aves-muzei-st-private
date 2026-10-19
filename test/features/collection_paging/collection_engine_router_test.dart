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
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves_model/aves_model.dart';
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

  AvesEntry entry(int id, {String? directory}) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '${directory ?? '/album'}/$id.jpg',
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
      // Nothing for the windowed path to serve: the scope itself needs memory.
      expect(decision.predicate, isNull);
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

    test('a below-threshold scope keeps its predicate when the library is too large', () async {
      await driftDb.insertEntries({entry(1), entry(2, directory: '/other'), entry(3, directory: '/other')});
      // One row in the scope, three in the library: the scope is small, but the
      // library is at the threshold, so a full load would materialize it all.
      await configure(engine: CollectionEngine.auto, threshold: 2);
      final decision = await router.resolve(filters: {StoredAlbumFilter('/album', null)}, database: driftDb);
      expect(decision.route, CollectionRoute.legacy);
      expect(decision.total, 1);
      expect(decision.reason, 'below the large-collection threshold');
      // Kept so the lens can page this scope instead of refusing it.
      expect(decision.predicate, isNotNull);
      expect(await router.allowFullLoad(database: driftDb), isFalse);
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

    test('a locked vault still pages, and its rows stay hidden', () async {
      // The vault's rows live in the database (they are inserted when it is
      // unlocked), so a locked vault needs the predicate's exclusion rather than
      // the in-memory path.
      const details = VaultDetails(name: 'v', autoLockScreenOff: true, useBin: false, lockType: VaultLockType.system);
      await vaults.create(details);
      final vaultDir = details.path;
      try {
        await driftDb.insertEntries({entry(1), entry(2, directory: vaultDir), entry(3, directory: '$vaultDir/sub')});
        vaults.lock({vaultDir});
        // The probe counts the visible rows, so the threshold is the visible one.
        await configure(engine: CollectionEngine.auto, threshold: 1);

        final decision = await router.resolve(filters: {}, database: driftDb);
        expect(decision.route, CollectionRoute.paged);
        // The vault's own row and a file nested under it are both hidden.
        expect(decision.total, 1);
      } finally {
        await vaults.remove({vaultDir});
      }
    });

    test('a failed probe keeps the legacy path', () async {
      await configure(engine: CollectionEngine.paged, threshold: 1);
      final decision = await router.resolve(filters: {}, database: _FailingDb());
      expect(decision.route, CollectionRoute.legacy);
      expect(decision.reason, isNotNull);
    });
  });

  group('CollectionEngineRouter.allowFullLoad', () {
    test('answers for the whole library, not for the scope', () async {
      await driftDb.insertEntries({for (var id = 1; id <= 10; id++) entry(id)});

      await configure(engine: CollectionEngine.auto, threshold: 11);
      expect(await router.allowFullLoad(database: driftDb), isTrue);

      await configure(engine: CollectionEngine.auto, threshold: 10);
      expect(await router.allowFullLoad(database: driftDb), isFalse);
    });

    test('honours an explicit legacy engine above the threshold', () async {
      await driftDb.insertEntries({for (var id = 1; id <= 10; id++) entry(id)});
      await configure(engine: CollectionEngine.legacy, threshold: 1);
      expect(await router.allowFullLoad(database: driftDb), isTrue);
    });

    test('a paged preference does not forbid a provably small full load', () async {
      await driftDb.insertEntries({entry(1)});
      await configure(engine: CollectionEngine.paged, threshold: 100000);
      expect(await router.allowFullLoad(database: driftDb), isTrue);
    });

    test('an unprovable size is not a safe full load', () async {
      await configure(engine: CollectionEngine.auto, threshold: 1);
      expect(await router.allowFullLoad(database: _FailingDb()), isFalse);
    });
  });
}

class _FailingDb extends FakeAvesDb {
  @override
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) => throw StateError('no database');
}
