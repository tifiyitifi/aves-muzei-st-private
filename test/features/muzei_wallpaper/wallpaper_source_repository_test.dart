import 'dart:io';
import 'dart:math';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_source_repository.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// `WallpaperSourceRepository`: the Drift translation of a wallpaper source.
///
/// The contract under test is that every call re-queries the database, always
/// restricts to still images, and honours hidden filters and locked vaults the
/// same way the collection views do.
void main() {
  late AppDatabase db;
  late DriftLocalMediaDb driftDb;
  late WallpaperSourceRepository repository;
  var nextId = 0;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();

    db = AppDatabase(NativeDatabase.memory());
    driftDb = DriftLocalMediaDb(database: db);
    await driftDb.init();
    // Vaults and settings resolve the database through the app-wide singleton.
    getIt.unregister<LocalMediaDb>();
    getIt.registerLazySingleton<LocalMediaDb>(() => driftDb);
  });

  tearDownAll(() async {
    await tearDownAllServices();
    await db.close();
  });

  setUp(() async {
    nextId = 0;
    await setUpServices();
    await vaults.clear();
    await driftDb.clearEntries();
    repository = WallpaperSourceRepository(database: driftDb, random: Random(7));
  });

  AvesEntry entry({
    int? id,
    String dir = '/album',
    String mime = 'image/jpeg',
    bool trashed = false,
    int? dateTaken,
  }) {
    final entryId = id ?? ++nextId;
    return AvesEntry(
      id: entryId,
      uri: 'content://$entryId',
      path: '$dir/$entryId.${mime.startsWith('video/') ? 'mp4' : 'jpg'}',
      contentId: 100 + entryId,
      pageId: null,
      sourceMimeType: mime,
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$entryId',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken ?? entryId * 10,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  WallpaperSourceScope collection({Set<CollectionFilter> filters = const {}}) => WallpaperSourceScope(kind: WallpaperSourceKind.myPhotos, filters: filters);

  WallpaperSourceScope single(int entryId) => WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: entryId);

  Future<int?> pickId(
    WallpaperSourceScope scope, {
    WallpaperOrdering ordering = WallpaperOrdering.inOrder,
    int cursor = 0,
    int attempt = 0,
    int newestEntryId = 0,
    Set<int> excludeEntryIds = const {},
  }) async {
    final pick = await repository.pick(
      scope,
      ordering: ordering,
      cursor: cursor,
      attempt: attempt,
      newestEntryId: newestEntryId,
      excludeEntryIds: excludeEntryIds,
    );
    return pick.entry?.id;
  }

  group('collection scope', () {
    test('only still images are eligible', () async {
      await driftDb.insertEntries({
        entry(id: 1, mime: 'image/jpeg', dateTaken: 10),
        entry(id: 2, mime: 'video/mp4', dateTaken: 20),
        entry(id: 3, mime: 'image/png', dateTaken: 30),
      });
      final scope = collection();

      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.ready);
      expect(resolution.total, 2);
      // The window uses the collection order: newest first.
      expect(await pickId(scope, cursor: 0), 3);
      expect(await pickId(scope, cursor: 1), 1);

      // The implicit image filter intersects with the scope, so a video-only
      // scope can never select a video.
      final videoScope = collection(filters: {MimeFilter.video});
      final videoResolution = await repository.resolve(videoScope);
      expect(videoResolution.status, WallpaperSourceStatus.empty);
      expect(await pickId(videoScope), isNull);
    });

    test('an album union (SetOrFilter) picks from every selected album', () async {
      await driftDb.insertEntries({
        entry(id: 1, dir: '/a', dateTaken: 10),
        entry(id: 2, dir: '/b', dateTaken: 20),
        entry(id: 3, dir: '/c', dateTaken: 30),
        entry(id: 4, dir: '/a', mime: 'video/mp4', dateTaken: 40),
      });
      final scope = collection(
        filters: {
          SetOrFilter({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)}),
        },
      );

      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.ready);
      expect(resolution.total, 2);
      // Newest first within the union, and the album video is still skipped.
      expect(await pickId(scope, cursor: 0), 2);
      expect(await pickId(scope, cursor: 1), 1);
    });

    test('in-order cursor wraps at both ends and shifts retries', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();

      // Newest first, the same whole-list order the collection views show.
      expect(await pickId(scope, cursor: 0), 3);
      expect(await pickId(scope, cursor: 1), 2);
      expect(await pickId(scope, cursor: 2), 1);
      // The cursor points past the last entry: wrap to the first.
      expect(await pickId(scope, cursor: 3), 3);
      expect(await pickId(scope, cursor: 4), 2);
      // A negative cursor must not escape the range either.
      expect(await pickId(scope, cursor: -1), 1);
      // A bake retry shifts by one entry instead of repeating the same photo.
      expect(await pickId(scope, cursor: 0, attempt: 1), 2);
    });

    test('random ordering is reproducible with a seed and stays in range', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 5; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();

      Future<List<int?>> sample(WallpaperSourceRepository source) async => [
        for (var i = 0; i < 12; i++) (await source.pick(scope, ordering: WallpaperOrdering.random, cursor: 0)).entry?.id,
      ];

      final first = await sample(WallpaperSourceRepository(database: driftDb, random: Random(1234)));
      final second = await sample(WallpaperSourceRepository(database: driftDb, random: Random(1234)));
      expect(first, second);
      expect(first, everyElement(isIn({1, 2, 3, 4, 5})));
    });

    test('random ordering avoids the current and recently shown artworks', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();
      // Seeded so the rejection sampling is reproducible.
      final seeded = WallpaperSourceRepository(database: driftDb, random: Random(7));

      for (var i = 0; i < 8; i++) {
        final pick = await seeded.pick(
          scope,
          ordering: WallpaperOrdering.random,
          cursor: 0,
          excludeEntryIds: {1, 2, 3},
        );
        expect(pick.entry?.id, 4, reason: 'only the non-recent artwork is eligible');
      }

      // A library barely larger than the exclusion set must repeat rather than
      // return nothing.
      final repeat = await seeded.pick(
        scope,
        ordering: WallpaperOrdering.random,
        cursor: 0,
        excludeEntryIds: {1, 2, 3, 4},
      );
      expect(repeat.entry, isNotNull);
    });

    test('new-then-random serves entries added after the marker, in id order', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 5; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();

      expect(await pickId(scope, ordering: WallpaperOrdering.newThenRandom, newestEntryId: 2), 3);
      expect(await pickId(scope, ordering: WallpaperOrdering.newThenRandom, newestEntryId: 3), 4);
      // A bake retry steps to the next new photo instead of repeating.
      expect(await pickId(scope, ordering: WallpaperOrdering.newThenRandom, newestEntryId: 2, attempt: 1), 4);
      // Everything is old: fall back to random, like Muzei.
      expect(await pickId(scope, ordering: WallpaperOrdering.newThenRandom, newestEntryId: 5), isNotNull);
    });

    test('the new-photo marker seeds from the newest artwork', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
      });
      expect(await repository.newestEntryId(collection()), 3);
    });

    test('an empty library resolves empty and picks nothing', () async {
      final scope = collection();
      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.empty);
      expect(resolution.total, 0);

      final pick = await repository.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 3);
      expect(pick.status, WallpaperSourceStatus.empty);
      expect(pick.hasEntry, isFalse);
    });

    test('filters that need the in-memory path resolve unsupported', () async {
      await driftDb.insertEntries({entry(id: 1)});
      final scope = collection(filters: {QueryFilter('/regex/', ACalendar.gregorian)});

      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.unsupported);
      expect(resolution.reason, isNotNull);

      final pick = await repository.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 0);
      expect(pick.status, WallpaperSourceStatus.unsupported);
      expect(pick.entry, isNull);
    });

    test('hidden filters are excluded', () async {
      await driftDb.insertEntries({
        entry(id: 1, dir: '/visible'),
        entry(id: 2, dir: '/hidden'),
      });
      final old = settings.hiddenFilters;
      try {
        settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
        final scope = collection();

        expect((await repository.resolve(scope)).total, 1);
        expect(await pickId(scope, cursor: 0), 1);
        expect(await pickId(scope, cursor: 1), 1);
      } finally {
        settings.hiddenFilters = old;
      }
    });

    test('locked vault entries are excluded, including nested directories', () async {
      const details = VaultDetails(name: 'v', autoLockScreenOff: true, useBin: false, lockType: VaultLockType.system);
      await vaults.create(details);
      final vaultDir = details.path;
      try {
        await driftDb.insertEntries({
          entry(id: 1, dir: '/visible'),
          entry(id: 2, dir: vaultDir),
          entry(id: 3, dir: '$vaultDir/sub'),
        });
        vaults.lock({vaultDir});
        final scope = collection();

        expect((await repository.resolve(scope)).total, 1);
        expect(await pickId(scope, cursor: 0), 1);
      } finally {
        await vaults.remove({vaultDir});
      }
    });

    test('a deleted entry is skipped by the next query', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();
      expect(await pickId(scope, cursor: 1), 2);

      await driftDb.removeIds({2});

      // The count and the window are re-read, so the cursor now lands on the
      // entry that followed the deleted one.
      expect((await repository.resolve(scope)).total, 2);
      expect(await pickId(scope, cursor: 1), 1);
      expect(await pickId(scope, cursor: 2), 3);
    });

    test('pickAt normalizes offsets for the retry loop', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = collection();

      expect((await repository.pickAt(scope, total: 3, offset: -1))?.id, 1);
      expect((await repository.pickAt(scope, total: 3, offset: 2))?.id, 1);
      expect((await repository.pickAt(scope, total: 3, offset: 3))?.id, 3);
      expect((await repository.pickAt(scope, total: 3, offset: 4))?.id, 2);
      expect(await repository.pickAt(scope, total: 0, offset: 0), isNull);
    });
  });

  group('single scope', () {
    test('resolves and returns the chosen artwork regardless of cursor/ordering', () async {
      await driftDb.insertEntries({entry(id: 5)});
      final scope = single(5);

      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.ready);
      expect(resolution.total, 1);

      final pick = await repository.pick(scope, ordering: WallpaperOrdering.random, cursor: 42);
      expect(pick.status, WallpaperSourceStatus.ready);
      expect(pick.entry?.id, 5);
      expect(pick.offset, 0);
      // A single source has one position, so any offset wraps back to it.
      expect((await repository.pickAt(scope, total: 1, offset: 1))?.id, 5);
    });

    test('every ordering returns the chosen artwork, never the library', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 5; id++) entry(id: id, dateTaken: id * 10),
      });
      final scope = single(2);

      for (final ordering in WallpaperOrdering.values) {
        // A high marker and an exclusion that contains the entry must not make
        // the single scope fall through to another photo.
        final pick = await repository.pick(
          scope,
          ordering: ordering,
          cursor: 0,
          newestEntryId: 99,
          excludeEntryIds: {2},
        );
        expect(pick.entry?.id, 2, reason: 'ordering $ordering');
      }
      expect(await repository.newestEntryId(scope), 2);
    });

    test('a missing entry resolves missing', () async {
      final scope = single(999);

      final resolution = await repository.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.missing);

      final pick = await repository.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 0);
      expect(pick.status, WallpaperSourceStatus.missing);
      expect(pick.entry, isNull);

      // A single scope is not configured until an entry has been chosen.
      final unset = WallpaperSourceScope(kind: WallpaperSourceKind.single);
      expect((await repository.resolve(unset)).status, WallpaperSourceStatus.missing);
    });

    test('a video, a trashed entry or a locked vault entry is not usable', () async {
      const details = VaultDetails(name: 'v', autoLockScreenOff: true, useBin: false, lockType: VaultLockType.system);
      await vaults.create(details);
      final vaultDir = details.path;
      try {
        await driftDb.insertEntries({
          entry(id: 6, mime: 'video/mp4'),
          entry(id: 7, trashed: true),
          entry(id: 8, dir: vaultDir),
        });
        vaults.lock({vaultDir});

        for (final id in [6, 7, 8]) {
          expect((await repository.resolve(single(id))).status, WallpaperSourceStatus.missing, reason: 'entry $id');
        }
      } finally {
        await vaults.remove({vaultDir});
      }
    });

    test('an explicit choice overrides hidden filters', () async {
      await driftDb.insertEntries({entry(id: 9, dir: '/hidden')});
      final old = settings.hiddenFilters;
      try {
        settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};

        expect((await repository.resolve(single(9))).status, WallpaperSourceStatus.ready);
        expect(await pickId(single(9)), 9);
      } finally {
        settings.hiddenFilters = old;
      }
    });
  });

  group('single artwork copy', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('aves_muzei_repo_');
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; the assertion result is more useful.
      }
    });

    WallpaperSourceRepository copyRepository(WallpaperSingleArtwork artwork) => WallpaperSourceRepository(
      database: driftDb,
      random: Random(7),
      stateRoot: root,
      singleArtwork: () => artwork,
    );

    Future<WallpaperSingleArtwork> writeCopy(int entryId) async {
      const relative = 'source/single.jpg';
      final file = File(p.join(root.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const [1, 2, 3]);
      return WallpaperSingleArtwork(
        relativePath: relative,
        entryId: entryId,
        mimeType: 'image/jpeg',
        title: 'copy',
        width: 10,
        height: 20,
        sizeBytes: 3,
      );
    }

    WallpaperSourceScope copyScope(WallpaperSingleArtwork artwork) => WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: artwork.entryId, singleArtwork: artwork);

    test('the copy is the artwork even after the library row is gone', () async {
      final artwork = await writeCopy(42);
      final repositoryUnderTest = copyRepository(artwork);
      final scope = copyScope(artwork);

      final resolution = await repositoryUnderTest.resolve(scope);
      expect(resolution.status, WallpaperSourceStatus.ready);
      expect(resolution.total, 1);

      final pick = await repositoryUnderTest.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 0);
      final file = File(p.join(root.path, artwork.relativePath));
      expect(pick.entry, isNotNull);
      expect(pick.entry!.uri, file.uri.toString());
      expect(pick.entry!.path, file.path);
      expect(pick.entry!.mimeType, 'image/jpeg');
      expect(pick.entry!.sourceTitle, 'copy');
      expect(pick.entry!.bestTitle, 'copy', reason: 'the copy file name must not replace the original title');
      expect(pick.entry!.width, 10);
      expect(pick.entry!.height, 20);
      // A slot only stores the entry id, so validation must find the copy too.
      expect(await repositoryUnderTest.entryById(42), isNotNull);
    });

    test('the viewer entry prefers the library original over the copy', () async {
      final artwork = await writeCopy(42);
      await driftDb.insertEntries({entry(id: 42)});
      final repositoryUnderTest = copyRepository(artwork);

      final copy = await repositoryUnderTest.entryById(42);
      expect(copy?.path, File(p.join(root.path, artwork.relativePath)).path);

      final library = await repositoryUnderTest.libraryEntryById(42);
      expect(library, isNotNull);
      expect(library!.uri, 'content://42');
      expect(library.path, '/album/42.jpg');
    });

    test('libraryEntryById reports the original when only the copy is left', () async {
      final artwork = await writeCopy(43);
      final repositoryUnderTest = copyRepository(artwork);

      expect(await repositoryUnderTest.libraryEntryById(43), isNull);
      expect(await repositoryUnderTest.entryById(43), isNotNull, reason: 'the slot still resolves through the copy');
    });

    test('a missing copy falls back to the library entry', () async {
      final artwork = await writeCopy(5);
      await File(p.join(root.path, artwork.relativePath)).delete();
      await driftDb.insertEntries({entry(id: 5)});
      final repositoryUnderTest = copyRepository(artwork);
      final scope = copyScope(artwork);

      expect((await repositoryUnderTest.resolve(scope)).status, WallpaperSourceStatus.ready);
      final pick = await repositoryUnderTest.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 0);
      expect(pick.entry?.uri, 'content://5');
    });

    test('a copy and a library entry that are both gone report missing', () async {
      final artwork = await writeCopy(6);
      await File(p.join(root.path, artwork.relativePath)).delete();
      final repositoryUnderTest = copyRepository(artwork);
      final scope = copyScope(artwork);

      expect((await repositoryUnderTest.resolve(scope)).status, WallpaperSourceStatus.missing);
      expect((await repositoryUnderTest.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 0)).entry, isNull);
    });
  });

  test('10k-entry source keeps count and window interactive', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 10000; id++) entry(id: id, dateTaken: id * 10),
    });
    final scope = collection();

    final stopwatch = Stopwatch()..start();
    final resolution = await repository.resolve(scope);
    final pick = await repository.pick(scope, ordering: WallpaperOrdering.inOrder, cursor: 500);
    stopwatch.stop();

    expect(resolution.total, 10000);
    // Newest first: offset 500 is the 10,000th entry minus 500.
    expect(pick.entry?.id, 9500);
    // Recorded for the M3 gate; the bound is deliberately generous because a
    // timing assertion would be brittle on a shared CI machine.
    debugPrint('M3 10k resolve+pick: ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
