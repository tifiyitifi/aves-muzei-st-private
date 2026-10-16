import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/favourites.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/viewer/video_playback.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    // `pContext` (used by `loadEntries(directory:)`) is resolved from GetIt;
    // tests force a POSIX context so path handling matches the app.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late DriftLocalMediaDb service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = DriftLocalMediaDb(database: db);
    await service.init();
  });

  tearDown(() => db.close());

  AvesEntry entry(int id, {String? title}) {
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
      sourceTitle: title ?? 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: false,
      origin: 0,
    );
  }

  test('schema pins legacy camelCase column names', () async {
    final rows = await db.customSelect('PRAGMA table_info(entry)').get();
    final names = rows.map((r) => r.data['name']).toSet();
    expect(names, containsAll(<String>['id', 'contentId', 'sourceMimeType', 'sourceRotationDegrees', 'dateModifiedMillis', 'sourceDateTakenMillis']));

    final tableNames = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.data['name']).toSet();
    expect(tableNames, containsAll(<String>['entry', 'dateTaken', 'metadata', 'address', 'favourites', 'covers', 'dynamicAlbums', 'vaults', 'trash', 'videoPlayback', 'debug', 'appMeta']));
  });

  test('init retries after a transient failure instead of staying poisoned', () async {
    final provider = _FlakyDatabaseProvider(db);
    final flaky = DriftLocalMediaDb(provider: provider);
    await expectLater(flaky.init(), throwsA(isA<StateError>()));
    expect(provider.attempts, 1);

    // The failed attempt must be dropped so a later init can retry and succeed.
    await flaky.init();
    expect(provider.attempts, 2);

    final a = entry(flaky.nextId);
    await flaky.insertEntries({a});
    expect((await flaky.loadEntriesById({a.id})).single.path, a.path);
  });

  test('entries round trip, update and remove', () async {
    final a = entry(service.nextId);
    await service.insertEntries({a});

    final loaded = await service.loadEntriesById({a.id});
    expect(loaded.single.path, a.path);
    expect(loaded.single.contentId, a.contentId);

    await service.updateEntry(a.id, a.copyWith(sourceTitle: 'renamed'));
    expect((await service.loadEntriesById({a.id})).single.sourceTitle, 'renamed');

    final byDirectory = await service.loadEntries(directory: '/album');
    expect(byDirectory.map((e) => e.id), contains(a.id));

    await service.removeIds({a.id});
    expect(await service.loadEntriesById({a.id}), isEmpty);
  });

  test('searchLiveEntries and searchLiveDuplicates', () async {
    await service.insertEntries({entry(service.nextId, title: 'beach'), entry(service.nextId, title: 'mountain')});

    final found = await service.searchLiveEntries('beach');
    expect(found.map((e) => e.sourceTitle), ['beach']);

    final duplicateA = entry(service.nextId)..contentId = 777;
    final duplicateB = entry(service.nextId)..contentId = 777;
    await service.insertEntries({duplicateA, duplicateB});
    final duplicates = await service.searchLiveDuplicates(0, null);
    expect(duplicates.map((e) => e.contentId), contains(777));
  });

  test('catalog metadata and date taken', () async {
    final metadata = CatalogMetadata(
      id: 1,
      mimeType: 'image/jpeg',
      dateMillis: 5,
      rotationDegrees: 90,
      xmpSubjects: 'subject',
      xmpTitle: 'xmp',
      latitude: 1.5,
      longitude: 2.5,
      rating: 3,
    );
    await service.saveCatalogMetadata({metadata});

    final loaded = (await service.loadCatalogMetadataById({1})).single;
    expect(loaded.rating, 3);
    expect(loaded.rotationDegrees, 90);
    expect(loaded.latitude, 1.5);

    expect(await service.loadDates(), {1: 5});

    await service.updateCatalogMetadata(1, null);
    expect(await service.loadCatalogMetadataById({1}), isEmpty);
    expect(await service.loadDates(), isEmpty);
  });

  test('addresses', () async {
    const address = AddressDetails(id: 1, countryCode: 'US', countryName: 'United States', adminArea: 'CA', locality: 'SF');
    await service.saveAddresses({address});
    expect((await service.loadAddressesById({1})).single.locality, 'SF');

    await service.updateAddress(1, null);
    expect(await service.loadAddressesById({1}), isEmpty);
  });

  test('favourites', () async {
    await service.addFavourites({const FavouriteRow(entryId: 1)});
    expect((await service.loadAllFavourites()).map((r) => r.entryId), [1]);

    await service.removeFavourites({const FavouriteRow(entryId: 1)});
    expect(await service.loadAllFavourites(), isEmpty);
  });

  test('covers', () async {
    final filter = StoredAlbumFilter('/album', null);
    await service.addCovers({CoverRow(filter: filter, coverProps: const CoverProps(1, 'pkg', null))});
    expect((await service.loadAllCovers()).single.filter, filter);

    await service.removeCovers({filter});
    expect(await service.loadAllCovers(), isEmpty);
  });

  test('dynamic albums', () async {
    await service.addDynamicAlbums({DynamicAlbumRow(name: 'dyn', filter: StoredAlbumFilter('/album', null))});
    expect((await service.loadAllDynamicAlbums()).single.name, 'dyn');

    await service.removeDynamicAlbums({'dyn'});
    expect(await service.loadAllDynamicAlbums(), isEmpty);
  });

  test('video playback', () async {
    await service.addVideoPlayback({const VideoPlaybackRow(entryId: 1, resumeTimeMillis: 1234)});
    expect((await service.loadVideoPlayback(1))?.resumeTimeMillis, 1234);

    await service.removeVideoPlayback({1});
    expect(await service.loadVideoPlayback(1), isNull);
  });

  test('vaults', () async {
    const vault = VaultDetails(name: 'v', autoLockScreenOff: true, useBin: false, lockType: VaultLockType.system);
    await service.addVaults({vault});
    expect((await service.loadAllVaults()).single.autoLockScreenOff, isTrue);

    await service.updateVault('v', vault.copyWith(name: 'w'));
    expect((await service.loadAllVaults()).single.name, 'w');

    await service.removeVaults({vault.copyWith(name: 'w')});
    expect(await service.loadAllVaults(), isEmpty);
  });

  test('trash', () async {
    await service.updateTrash(1, const TrashDetails(id: 1, path: '/trash/1', dateMillis: 9));
    expect((await service.loadAllTrashDetails()).single.path, '/trash/1');

    await service.updateTrash(1, null);
    expect(await service.loadAllTrashDetails(), isEmpty);
  });

  test('debug log', () async {
    await service.addDebugLog('hello');
    expect(await service.loadAllDebugLog(), ['hello']);

    await service.clearDebugLog();
    expect(await service.loadAllDebugLog(), isEmpty);
  });
}

/// An [AppDatabaseProvider] whose first connection attempt fails, to exercise
/// [AppDatabaseProvider.open]'s retry (and, through it, `init` retry).
class _FlakyDatabaseProvider extends AppDatabaseProvider {
  final AppDatabase _delegate;
  var attempts = 0;

  new(this._delegate);

  @override
  bool get isInjected => true;

  @override
  Future<AppDatabase> createDatabase() async {
    if (attempts++ == 0) throw StateError('transient open failure');
    return _delegate;
  }
}
