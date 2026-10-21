import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/lens/scope_registry.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// The scope memory that keeps a view across navigation: a scope comes back as
/// the lens it was (window published), another scope replaces it, and a parked
/// lens never drives the library-wide state.
void main() {
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
    // Page even the small scopes these tests seed: the point is the scope
    // memory, not the threshold.
    await collectionPagingPrefs.setLargeThreshold(1);
    await collectionPagingPrefs.setImportComplete(true);
    await driftDb.clearEntries();
    await driftDb.clearCatalogMetadata();
    await driftDb.clearDates();
    await driftDb.clearAddresses();
    await driftDb.clearTrashDetails();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    scopeRegistry.reset();
    mediaSetTab.clear();
    await setUpServices();
  });

  AvesEntry entry(int id, {String dir = '/a'}) {
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
      sourceDateTakenMillis: 0,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  Set<CollectionFilter?> scopeOf(String? album) => album == null ? {} : {StoredAlbumFilter(album, null)};

  Future<void> settle(PagedCollectionLens lens, {required bool Function() done}) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('scope view did not settle (entryCount=${lens.entryCount}, paged=${lens.pagedActive}, state=${lens.source.state})');
  }

  group('ScopeRegistry', () {
    test('a scope keeps its lens, so coming back is a repaint', () async {
      await driftDb.insertEntries({entry(1), entry(2), entry(3, dir: '/b')});

      final home = scopeRegistry.acquire(source: source, filters: scopeOf(null));
      await home.ready;
      expect(home.pagedActive, isTrue);
      expect(home.entryCount, 3);

      final album = scopeRegistry.acquire(source: source, filters: scopeOf('/a'));
      await album.ready;
      expect(album.entryCount, 2);
      scopeRegistry.release(home);
      scopeRegistry.release(album);

      // The same view, already resolved: the page paints it on its first frame
      // instead of showing a loading body while the rows are read again.
      final again = scopeRegistry.acquire(source: source, filters: scopeOf(null));
      expect(identical(again, home), isTrue);
      expect(again.pagedActive, isTrue);
      expect(again.entryCount, 3);
      expect(scopeRegistry.active, same(again));
    });

    test('the media-set slot reopens the album it showed, from the retained lens', () async {
      await driftDb.insertEntries({entry(1), entry(2), entry(3, dir: '/b')});

      final album = scopeRegistry.acquire(source: source, filters: scopeOf('/a'));
      await album.ready;
      expect(album.entryCount, 2);
      scopeRegistry.release(album);
      // The albums page is on screen: no collection page is mounted, and the slot
      // holds the filters of the view it was showing.
      mediaSetTab.note(routeFilters: scopeOf('/a').nonNulls.toSet(), currentFilters: () => album.filters);

      // Tapping the bottom bar's media-set item must land on that view, instead of
      // opening a fresh "whole library" scope that resolves everything again.
      final again = scopeRegistry.acquire(source: source, filters: mediaSetTab.filters);
      expect(identical(again, album), isTrue);
      expect(again.entryCount, 2);
      expect(again.ready, completes);
    });

    test('another album replaces the previous one, the home stays', () async {
      await driftDb.insertEntries({entry(1), entry(2, dir: '/b')});

      final home = scopeRegistry.acquire(source: source, filters: scopeOf(null));
      await home.ready;
      final first = scopeRegistry.acquire(source: source, filters: scopeOf('/a'));
      await first.ready;
      // A route transition mounts the next page before the previous one is
      // disposed, so the releases land after the acquisition.
      scopeRegistry.release(home);
      final second = scopeRegistry.acquire(source: source, filters: scopeOf('/b'));
      await second.ready;
      scopeRegistry.release(first);

      expect(identical(first, second), isFalse);
      expect(first.lensAlive, isFalse, reason: 'the album that was left is discarded');
      expect(home.lensAlive, isTrue, reason: 'the way back to the library is pinned');
      expect(scopeRegistry.scopeCount, 2);
    });

    test('a scope keeps the filters the user left it with', () async {
      await driftDb.insertEntries({entry(1), entry(2), entry(3, dir: '/b')});
      final albumFilters = scopeOf('/a');

      final album = scopeRegistry.acquire(source: source, filters: albumFilters);
      await album.ready;
      expect(album.entryCount, 2);
      // The in-view filter change (the title search, a chip) is remembered too.
      album.setFilters({});
      await settle(album, done: () => album.entryCount == 3);
      scopeRegistry.release(album);

      final again = scopeRegistry.acquire(source: source, filters: albumFilters);
      expect(identical(again, album), isTrue);
      expect(again.pagedActive, isTrue);
      expect(again.entryCount, 3, reason: 'the extra filters the view carried are restored');
    });

    test('the scope its route named is always part of its filters', () async {
      await driftDb.insertEntries({entry(1), entry(2)});
      final albumFilters = scopeOf('/a');

      final album = scopeRegistry.acquire(source: source, filters: albumFilters);
      await album.ready;
      // Clearing the chips (the clear action) leaves the album scope for a
      // moment; the scope itself is still that album.
      album.setFilters({});
      await settle(album, done: () => album.entryCount == 2);
      scopeRegistry.release(album);

      final again = scopeRegistry.acquire(source: source, filters: albumFilters);
      expect(identical(again, album), isTrue);
      expect(again.filters.whereType<StoredAlbumFilter>().map((v) => v.album), ['/a']);
    });

    test('two pages on one scope share the lens and keep it alive', () async {
      await driftDb.insertEntries({entry(1)});
      final filters = scopeOf('/a');

      final first = scopeRegistry.acquire(source: source, filters: filters);
      final second = scopeRegistry.acquire(source: source, filters: filters);
      expect(identical(first, second), isTrue);
      await first.ready;

      scopeRegistry.release(first);
      expect(first.lensAlive, isTrue);
      scopeRegistry.release(second);
      expect(first.lensAlive, isTrue, reason: 'retained views are parked, not disposed');
      expect(first.pagedActive, isTrue);
    });

    test('a prewarmed view resolves while nothing shows it', () async {
      await driftDb.insertEntries({entry(1), entry(2, dir: '/b')});
      final home = scopeRegistry.acquire(source: source, filters: scopeOf(null));
      await home.ready;
      expect(source.state, isNot(SourceState.loading));

      final albumFilters = scopeOf('/a');
      final prewarmed = scopeRegistry.prewarm(source: source, filters: albumFilters);
      expect(prewarmed, isNotNull);
      expect(prewarmed!.isActive, isFalse, reason: 'nothing shows it yet');

      // The resolve runs before its page exists, and the view on screen is never
      // told to wait for it: the shared state stays whatever that page made it.
      await prewarmed.ready;
      expect(prewarmed.pagedActive, isTrue);
      expect(prewarmed.entryCount, 1);
      expect(scopeRegistry.active, same(home));
      expect(source.state, isNot(SourceState.loading));

      // The page that opens it adopts the very same lens.
      final adopted = scopeRegistry.acquire(source: source, filters: albumFilters);
      expect(identical(adopted, prewarmed), isTrue);
      expect(adopted.pagedActive, isTrue);
    });

    test('a settled library resolves on the first visit instead of waiting on itself', () async {
      await driftDb.insertEntries({entry(1), entry(2), entry(3, dir: '/b')});
      // Everything catalogued, as it is on a device that has used the app for a
      // while: nothing runs alongside the resolve, so activation announcing the
      // wait would leave it waiting for the resolve it just delayed.
      await driftDb.saveCatalogMetadata({CatalogMetadata(id: 1), CatalogMetadata(id: 2), CatalogMetadata(id: 3)});

      final home = scopeRegistry.acquire(source: source, filters: scopeOf(null));
      await settle(home, done: () => home.pagedActive);
      expect(home.entryCount, 3);
      expect(home.awaitingFirstWindow, isFalse);
      expect(source.state, isNot(SourceState.loading));

      // The album opened next behaves the same.
      final album = scopeRegistry.acquire(source: source, filters: scopeOf('/a'));
      await settle(album, done: () => album.pagedActive);
      expect(album.entryCount, 2);
      expect(source.state, isNot(SourceState.loading));
    });

    test('the scope key names the filters, not the order they arrive in', () {
      final a = StoredAlbumFilter('/a', null);
      final b = StoredAlbumFilter('/b', null);
      expect(scopeKeyOf({a, b}), scopeKeyOf({b, a}));
      expect(scopeKeyOf({a}), isNot(scopeKeyOf({b})));
      expect(scopeKeyOf({}), isEmpty);
    });
  });
}
