import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_bake.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_prefetch_setting.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_single_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_state.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_single_artwork_store.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_source_repository.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

/// `WallpaperController`: slot rotation, generation, state/runtime files,
/// prefetch and recovery from an empty or broken source.
void main() {
  late AppDatabase db;
  late DriftLocalMediaDb driftDb;
  late WallpaperPrefs prefs;
  late Directory tempDir;
  late WallpaperStateStore store;
  late FakeWallpaperBaker baker;
  late FakeWallpaperBridge bridge;
  late WallpaperController controller;
  var nextId = 0;

  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();

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
    nextId = 0;
    SharedPreferences.setMockInitialValues({});
    await setUpServices();
    await vaults.clear();
    await driftDb.clearEntries();
    prefs = WallpaperPrefs();
    await prefs.init();
    await prefs.setAutoAdvance(const WallpaperAutoAdvance(ordering: WallpaperOrdering.inOrder));
    tempDir = await Directory.systemTemp.createTemp('aves_muzei_controller_');
    store = WallpaperStateStore(tempDir);
    baker = FakeWallpaperBaker();
    bridge = FakeWallpaperBridge();
    // The shared tests pin the original single-spare contract; the two-ahead
    // queue and the setting that enables it have their own tests below.
    controller = WallpaperController(
      prefs: prefs,
      repository: WallpaperSourceRepository(database: driftDb, random: Random(7)),
      baker: baker,
      store: store,
      bridge: bridge,
      targetSize: () async => const Size(100, 100),
      prefetchAhead: () => false,
    );
  });

  tearDown(() async {
    controller.dispose();
    prefs.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; the assertion result is more useful.
    }
  });

  AvesEntry entry({
    int? id,
    String dir = '/album',
    String mime = 'image/jpeg',
    int? dateTaken,
  }) {
    final entryId = id ?? ++nextId;
    return AvesEntry(
      id: entryId,
      uri: 'content://$entryId',
      path: '$dir/$entryId.jpg',
      contentId: 100 + entryId,
      pageId: null,
      sourceMimeType: mime,
      width: 100,
      height: 100,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$entryId',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken ?? entryId * 10,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  WallpaperController controllerWith({
    required WallpaperBaker baker,
    required WallpaperBridge bridge,
    required WallpaperStateStore store,
    bool Function()? prefetchAhead,
  }) => WallpaperController(
    prefs: prefs,
    repository: WallpaperSourceRepository(database: driftDb, random: Random(7)),
    baker: baker,
    store: store,
    bridge: bridge,
    targetSize: () async => const Size(100, 100),
    prefetchAhead: prefetchAhead ?? () => false,
  );

  group('single artwork copy', () {
    const artwork = WallpaperSingleArtwork(
      relativePath: 'source/single.jpg',
      entryId: 99,
      mimeType: 'image/jpeg',
      width: 100,
      height: 100,
      sizeBytes: 3,
    );

    Future<File> seedCopy() async {
      final file = File(p.join(tempDir.path, WallpaperSingleArtworkStore.sourceDirName, 'single.jpg'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const [1, 2, 3]);
      return file;
    }

    test('a single scope keeps the copy', () async {
      await controller.init();
      await controller.idle;
      final file = await seedCopy();

      await controller.setScope(WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 99, singleArtwork: artwork));
      await controller.idle;

      expect(await file.exists(), isTrue);
      expect(prefs.scope.singleArtwork, artwork);
    });

    test('switching away keeps the copy and the snapshot', () async {
      await controller.init();
      await controller.idle;
      final file = await seedCopy();

      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 99, singleArtwork: artwork);
      await controller.setScope(single);
      await controller.idle;
      await controller.setScope(single.copyWith(kind: WallpaperSourceKind.myPhotos));
      await controller.idle;

      expect(await file.exists(), isTrue, reason: 'the chosen photo may be gone from the library');
      expect(prefs.scope.singleArtwork, artwork, reason: 'switching back must not need a new pick');
      expect(prefs.scope.activeSingleArtwork, isNull, reason: 'the copy is not the library while the source is my photos');
    });

    test('switching back to single keeps using the same copy', () async {
      await controller.init();
      await controller.idle;
      final file = await seedCopy();

      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 99, singleArtwork: artwork);
      await controller.setScope(single);
      await controller.idle;
      await controller.setScope(single.copyWith(kind: WallpaperSourceKind.myPhotos));
      await controller.idle;
      await controller.setScope(prefs.scope.copyWith(kind: WallpaperSourceKind.single));
      await controller.idle;

      expect(prefs.scope.kind, WallpaperSourceKind.single);
      expect(prefs.scope.activeSingleArtwork, artwork);
      expect(await file.exists(), isTrue);
    });

    test('editing the inactive My photos filters leaves the wallpaper alone', () async {
      await driftDb.insertEntries({entry(id: 1), entry(id: 2)});
      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 1);
      await controller.setScope(single);
      await controller.idle;

      final current = controller.current!;
      final generation = controller.state.generation;
      final bakes = baker.bakeCalls;

      await controller.setScope(single.copyWith(filters: {FavouriteFilter.instance}));
      await controller.idle;

      expect(controller.current?.id, current.id);
      expect(controller.current?.artwork.entryId, current.artwork.entryId);
      expect(controller.state.generation, generation, reason: 'the wallpaper must not rebake');
      expect(baker.bakeCalls, bakes, reason: 'the wallpaper must not decode again');
      expect(prefs.scope.filters, contains(FavouriteFilter.instance), reason: 'the edit is still persisted');
      expect(prefs.scope.kind, WallpaperSourceKind.single);
    });

    test('an unconfigured source stops the feature but keeps the baked wallpaper', () async {
      await driftDb.insertEntries({entry(id: 1), entry(id: 2)});
      await controller.init();
      await controller.idle;
      final current = controller.current!;

      final unconfigured = WallpaperSourceScope(kind: WallpaperSourceKind.single, filters: {FavouriteFilter.instance});
      await controller.setScope(unconfigured);
      await controller.idle;

      expect(controller.current?.id, current.id, reason: 'the desktop keeps the artwork already shown');
      expect(controller.resolution?.status, WallpaperSourceStatus.missing);
      expect(prefs.scope.kind, WallpaperSourceKind.single);
      expect(prefs.scope.filters, contains(FavouriteFilter.instance), reason: 'the other source is still editable');
    });

    test('a restart keeps the last single artwork after its copy was deleted', () async {
      await driftDb.insertEntries({entry(id: 1)});
      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 1, singleArtwork: artwork);
      await controller.setScope(single);
      await controller.idle;
      final file = await seedCopy();
      final current = controller.current!;

      expect(await controller.removeSingleCopy(scope: single.copyWith(clearSingleArtwork: true)), isTrue);
      expect(await file.exists(), isFalse);

      // Both the original and the copy are gone now, so the source cannot bake
      // again; the baked wallpaper must still be the one on screen.
      await driftDb.clearEntries();
      final restarted = controllerWith(baker: baker, bridge: bridge, store: store);
      try {
        await restarted.init();
        await restarted.idle;

        expect(restarted.current?.id, current.id);
        expect(restarted.current?.artwork.entryId, current.artwork.entryId);
        expect(restarted.resolution?.status, WallpaperSourceStatus.missing);
      } finally {
        restarted.dispose();
      }
    });

    test('removeSingleCopy deletes the copy but keeps the baked wallpaper and the id', () async {      await driftDb.insertEntries({entry(id: 1), entry(id: 2)});
      final copy = WallpaperSingleArtwork(
        relativePath: artwork.relativePath,
        entryId: 1,
        mimeType: artwork.mimeType,
        width: artwork.width,
        height: artwork.height,
        sizeBytes: artwork.sizeBytes,
      );
      final single = WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 1, singleArtwork: copy);
      await controller.setScope(single);
      await controller.idle;
      final file = await seedCopy();

      final current = controller.current!;
      final generation = controller.state.generation;
      final removed = await controller.removeSingleCopy(scope: single.copyWith(clearSingleArtwork: true));

      expect(removed, isTrue);
      expect(await file.exists(), isFalse);
      expect(prefs.scope.singleEntryId, 1, reason: 'the original may still exist and keeps driving the source');
      expect(prefs.scope.singleArtwork, isNull);
      expect(controller.current?.id, current.id, reason: 'the baked wallpaper is not the copy');
      expect(controller.current?.artwork.entryId, current.artwork.entryId);
      expect(controller.state.generation, generation);
      expect(controller.state.sourceRevision, prefs.scope.revision);
      expect(controller.resolution?.isReady, isTrue, reason: 'the original is still in the library');
    });
  });

  test('init bakes the newest entry, writes state and prefetches the next', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
    });

    await controller.init();
    await controller.idle;

    expect(controller.initialized, isTrue);
    expect(controller.current?.artwork.entryId, 3, reason: 'newest first, in-order cursor starts at 0');
    expect(controller.next, isNotNull, reason: 'prefetch fills the second slot');
    expect(controller.next?.id, isNot(controller.current?.id));

    final state = await store.readState();
    expect(state, isNotNull);
    expect(state!.generation, greaterThanOrEqualTo(1));
    expect(state.current, controller.current!.id);
    expect(state.next, controller.next!.id);
    expect(state.sourceRevision, prefs.scope.revision);

    final sharp = store.slotFile(state.current, WallpaperSlotFiles.sharpName);
    expect(await sharp.exists(), isTrue);
    expect(await store.slotFile(state.current, WallpaperSlotFiles.artworkName).exists(), isTrue);

    // The controller invalidates the native runtime after each state write.
    expect((await store.readRuntime())?.generation, -1);
    expect(bridge.reloads, greaterThanOrEqualTo(2), reason: 'current bake and prefetch reload the renderer');
  });

  test('advance promotes the prefetched slot without baking again', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final first = controller.current!;
    final prefetched = controller.next!;
    final generation = controller.state.generation;
    final bakes = baker.bakeCalls;

    await controller.advance();

    expect(controller.current?.artwork.entryId, prefetched.artwork.entryId);
    expect(controller.current?.id, prefetched.id);
    expect(controller.current?.id, isNot(first.id));
    expect(controller.state.generation, greaterThan(generation));
    expect(baker.bakeCalls, bakes, reason: 'promotion must not decode the artwork again');
    expect(controller.state.next, -1);

    await controller.idle;
    expect(controller.next, isNotNull, reason: 'the freed slot is refilled in the background');
    expect(controller.next?.artwork.entryId, isNot(prefetched.artwork.entryId));
  });

  test('an empty source writes no wallpaper files', () async {
    await controller.init();
    await controller.idle;

    expect(controller.current, isNull);
    expect(controller.resolution?.status, WallpaperSourceStatus.empty);
    expect(controller.state.current, -1);
    expect(await store.slotFile(0, WallpaperSlotFiles.sharpName).exists(), isFalse);
    expect(await store.slotFile(1, WallpaperSlotFiles.sharpName).exists(), isFalse);
  });

  test('a failed bake skips to the next offset', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
    });
    baker.failingEntryIds.add(3);

    await controller.init();
    await controller.idle;

    expect(controller.current?.artwork.entryId, 2);
    expect(baker.bakeCalls, greaterThanOrEqualTo(2));
    expect(baker.attemptedEntryIds, containsAllInOrder([3, 2]));
  });

  test('syncRuntime adopts the slot the renderer switched to', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final state = await store.readState();
    final nativeCurrent = controller.next!;
    await store.writeRuntime(
      WallpaperRuntime(
        generation: state!.generation,
        current: nativeCurrent.id,
        next: -1,
        refillRequested: true,
      ),
    );

    await controller.syncRuntime();

    expect(controller.current?.artwork.entryId, nativeCurrent.artwork.entryId);
    expect(controller.state.next, -1);
    await controller.idle;
    expect(controller.next, isNotNull, reason: 'the refill request is served');
  });

  test('syncRuntime adopts a state a background run advanced to', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final before = (await store.readState())!;
    final advanced = controller.next!;
    // Simulate the headless auto-advance: it promotes `next` from another
    // isolate, so this controller only sees the newer file.
    await store.writeState(
      before.copyWith(
        generation: before.generation + 1,
        current: advanced.id,
        next: -1,
        slots: [advanced],
      ),
    );

    await controller.syncRuntime();

    expect(controller.current?.artwork.entryId, advanced.artwork.entryId, reason: 'the preview catches up without a restart');
    await controller.idle;
    expect(controller.next, isNotNull, reason: 'the freed slot is refilled');
  });

  test('a background fill of the free slot is adopted instead of baking twice', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final before = (await store.readState())!;
    final bakes = baker.bakeCalls;
    final free = controller.current!.id == 0 ? 1 : 0;
    final external = WallpaperSlot(
      id: free,
      artwork: WallpaperArtwork(
        entryId: 99,
        uri: 'content://99',
        files: WallpaperSlotFiles(
          sharp: WallpaperStateStore.relativeSlotFile(free, WallpaperSlotFiles.sharpName),
          effectsHome: WallpaperStateStore.relativeSlotFile(free, WallpaperSlotFiles.effectsHomeName),
          effectsLock: WallpaperStateStore.relativeSlotFile(free, WallpaperSlotFiles.effectsLockName),
        ),
      ),
    );
    await store.writeState(
      before.copyWith(
        generation: before.generation + 1,
        next: free,
        slots: [...before.slots.where((slot) => slot.id != free), external],
      ),
    );

    await controller.prefetch();

    expect(baker.bakeCalls, bakes, reason: 'the free slot is already filled');
    expect(controller.next?.artwork.entryId, 99);
  });

  test('auto-advance is only scheduled while the wallpaper is in use', () async {
    await controller.init();
    await controller.idle;

    // The fake wallpaper service starts inactive: there is nothing to advance.
    await controller.setAutoAdvance(const WallpaperAutoAdvance(interval: WallpaperInterval.h1));
    expect(bridge.autoAdvanceSeconds, 0);

    bridge.active = true;
    await controller.refreshServiceActive();
    expect(bridge.autoAdvanceSeconds, WallpaperInterval.h1.seconds);

    // Replacing the wallpaper must cancel the chain instead of baking in the dark.
    bridge.active = false;
    await controller.refreshServiceActive();
    expect(bridge.autoAdvanceSeconds, 0);
  });

  test('a restart reuses the baked slots without decoding again', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;
    final entryId = controller.current!.artwork.entryId;

    final secondBaker = FakeWallpaperBaker();
    final second = controllerWith(baker: secondBaker, bridge: FakeWallpaperBridge(), store: store);
    try {
      await second.init();
      await second.idle;

      expect(second.current?.artwork.entryId, entryId);
      expect(secondBaker.bakeCalls, 0, reason: 'state and both slots survived the restart');
    } finally {
      second.dispose();
    }
  });

  test('rapid effect changes keep the last value', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final first = controller.setEffects(
      const WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 100, dim: 0, grey: 0),
        lock: WallpaperEffects(blur: 100, dim: 0, grey: 0),
      ),
    );
    final second = controller.setEffects(
      const WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 200, dim: 0, grey: 0),
        lock: WallpaperEffects(blur: 200, dim: 0, grey: 0),
      ),
    );
    await Future.wait([first, second]);
    await controller.idle;

    expect(controller.state.effects.home.blur, 200);
    expect(baker.effectsHomeBlur, isNotEmpty);
    expect(baker.effectsHomeBlur.every((blur) => blur == 200), isTrue, reason: 'the superseded value is never baked');
    expect((await store.readState())?.effects.home.blur, 200);
  });

  test('setEffects rebakes only the effect images', () async {
    await driftDb.insertEntries({
      for (var id = 1; id <= 3; id++) entry(id: id, dateTaken: id * 10),
    });
    await controller.init();
    await controller.idle;

    final sharpFile = controller.currentFile!;
    final sharpBefore = await sharpFile.readAsBytes();
    final effectsCalls = baker.effectsCalls;

    await controller.setEffects(
      const WallpaperEffectsConfig(
        home: WallpaperEffects(blur: 100, dim: 0, grey: 0),
        lock: WallpaperEffects(blur: 0, dim: 0, grey: 0),
      ),
    );

    expect(baker.effectsCalls, greaterThan(effectsCalls));
    expect(await sharpFile.readAsBytes(), sharpBefore, reason: 'the sharp artwork is reused');
    expect(controller.state.effects.home.blur, 100);
    expect((await store.readState())?.effects.home.blur, 100);
  });

  test('a missing single artwork resolves missing and keeps an empty wall', () async {
    await prefs.setSourceScope(
      WallpaperSourceScope(kind: WallpaperSourceKind.single, singleEntryId: 999),
    );

    await controller.init();
    await controller.idle;

    expect(controller.current, isNull);
    expect(controller.resolution?.status, WallpaperSourceStatus.missing);
    expect(await store.slotFile(0, WallpaperSlotFiles.sharpName).exists(), isFalse);
  });

  group('two-ahead prefetch', () {
    test('bakes a spare for each of the first two taps', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 6; id++) entry(id: id, dateTaken: id * 10),
      });
      final deep = controllerWith(baker: baker, bridge: bridge, store: store, prefetchAhead: () => true);
      addTearDown(deep.dispose);

      await deep.init();
      await deep.idle;

      expect(deep.current, isNotNull);
      expect(deep.next, isNotNull, reason: 'the first spare serves the first tap');
      expect(deep.next2, isNotNull, reason: 'the second spare serves the second tap');
      expect({deep.current!.id, deep.next!.id, deep.next2!.id}, hasLength(3));

      final state = (await store.readState())!;
      expect(state.current, deep.current!.id);
      expect(state.next, deep.next!.id);
      expect(state.next2, deep.next2!.id);
      expect(state.slots, hasLength(3));
      for (final id in WallpaperController.slotIds) {
        expect(await store.slotFile(id, WallpaperSlotFiles.sharpName).exists(), isTrue, reason: 'slot $id is baked');
      }
    });

    test('keeps a single spare when the option is off', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 6; id++) entry(id: id, dateTaken: id * 10),
      });

      await controller.init();
      await controller.idle;

      expect(controller.next, isNotNull);
      expect(controller.next2, isNull);
      expect((await store.readState())!.next2, -1);
      expect(await store.slotDirectory(WallpaperController.thirdSlotId).exists(), isFalse);
    });

    test('a native promotion keeps the deeper spare promotable', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 6; id++) entry(id: id, dateTaken: id * 10),
      });
      final deep = controllerWith(baker: baker, bridge: bridge, store: store, prefetchAhead: () => true);
      addTearDown(deep.dispose);
      await deep.init();
      await deep.idle;

      final before = (await store.readState())!;
      final promoted = deep.next!;
      final spare = deep.next2!;
      // The renderer promotes `next` and keeps the deeper spare promotable.
      await store.writeRuntime(
        WallpaperRuntime(
          generation: before.generation,
          current: promoted.id,
          next: spare.id,
          refillRequested: true,
        ),
      );

      await deep.syncRuntime();

      expect(deep.current?.id, promoted.id);
      expect(deep.next?.id, spare.id, reason: 'the second tap must not wait for a bake');

      await deep.idle;
      expect(deep.next2, isNotNull, reason: 'the freed slot is baked again');
      expect({deep.current!.id, deep.next!.id, deep.next2!.id}, hasLength(3));
    });

    test('consuming the deepest spare refills both levels', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 6; id++) entry(id: id, dateTaken: id * 10),
      });
      final deep = controllerWith(baker: baker, bridge: bridge, store: store, prefetchAhead: () => true);
      addTearDown(deep.dispose);
      await deep.init();
      await deep.idle;

      final before = (await store.readState())!;
      final deepest = deep.next2!;
      await store.writeRuntime(
        WallpaperRuntime(generation: before.generation, current: deepest.id, next: -1, refillRequested: true),
      );

      await deep.syncRuntime();

      expect(deep.current?.id, deepest.id);
      expect(deep.state.next, -1);

      await deep.idle;
      expect(deep.next, isNotNull);
      expect(deep.next2, isNotNull);
      expect({deep.current!.id, deep.next!.id, deep.next2!.id}, hasLength(3));
    });

    test('a prefetch that loses a race to an advance still fills the queue', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 8; id++) entry(id: id, dateTaken: id * 10),
      });
      final deep = controllerWith(baker: baker, bridge: bridge, store: store, prefetchAhead: () => true);
      addTearDown(deep.dispose);
      await deep.init();
      await deep.idle;

      final before = (await store.readState())!;
      final firstPromoted = deep.next!;
      final secondPromoted = deep.next2!;
      // The renderer promoted the first spare; adopting it leaves the queue one
      // level short, so the refill is about to bake the freed slot.
      // An advance landing during that bake must not leave a hole.
      baker.fireOnBakeCall = baker.bakeCalls + 1;
      baker.onBake = deep.advance;
      await store.writeRuntime(
        WallpaperRuntime(
          generation: before.generation,
          current: firstPromoted.id,
          next: secondPromoted.id,
          refillRequested: true,
        ),
      );

      await deep.syncRuntime();
      await deep.idle;

      expect(deep.current?.id, secondPromoted.id, reason: 'the racing advance won');
      expect(deep.next, isNotNull);
      expect(deep.next2, isNotNull);
      expect({deep.current!.id, deep.next!.id, deep.next2!.id}, hasLength(3), reason: 'the aborted bake is retried, not dropped');
    });

    test('a tap promoted during a bake is not rewound by the commit', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 8; id++) entry(id: id, dateTaken: id * 10),
      });
      final deep = controllerWith(baker: baker, bridge: bridge, store: store, prefetchAhead: () => true);
      addTearDown(deep.dispose);
      await deep.init();
      await deep.idle;

      final before = (await store.readState())!;
      final firstPromoted = deep.next!;
      final secondPromoted = deep.next2!;
      // Tap 1: the renderer promoted the first spare and notified the page.
      await store.writeRuntime(
        WallpaperRuntime(
          generation: before.generation,
          current: firstPromoted.id,
          next: secondPromoted.id,
          refillRequested: true,
        ),
      );
      // Tap 2 lands while the refill is baking the freed slot.
      baker.fireOnBakeCall = baker.bakeCalls + 1;
      baker.onBake = () async {
        await store.writeRuntime(
          WallpaperRuntime(
            generation: before.generation,
            current: secondPromoted.id,
            next: -1,
            refillRequested: true,
          ),
        );
      };

      await deep.syncRuntime();
      await deep.idle;

      expect(deep.current?.id, secondPromoted.id, reason: 'the bake adopts the newer runtime instead of rewinding to the first promotion');
      expect(deep.state.next, isNotNull);
      expect(deep.next2, isNotNull);
      expect(deep.state.slots.map((slot) => slot.id), contains(secondPromoted.id));
    });

    test('the app setting decides the depth and defaults to on', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 6; id++) entry(id: id, dateTaken: id * 10),
      });
      WallpaperController production() => WallpaperController(
        prefs: prefs,
        repository: WallpaperSourceRepository(database: driftDb, random: Random(7)),
        baker: baker,
        store: store,
        bridge: bridge,
        targetSize: () async => const Size(100, 100),
      );

      final defaults = production();
      try {
        await defaults.init();
        await defaults.idle;
        expect(defaults.next2, isNotNull, reason: 'the option is on by default');
      } finally {
        defaults.dispose();
      }

      settings.set(WallpaperPrefetchSetting.key, false);
      final off = production();
      try {
        await off.init();
        await off.idle;
        expect(off.state.next2, -1);
        expect(off.state.slots, hasLength(2), reason: 'the deeper slot is dropped when the option is off');
      } finally {
        off.dispose();
      }
    });
  });

  group('recent artworks', () {
    test('advancing remembers the artwork it promotes, without slot paths', () async {
      await driftDb.insertEntries({
        for (var id = 1; id <= 4; id++) entry(id: id, dateTaken: id * 10),
      });

      await controller.init();
      await controller.idle;
      final first = controller.current!.artwork.entryId;
      expect(controller.state.recent.first.entryId, first);
      expect(controller.state.recent.first.files, WallpaperSlotFiles.empty);

      await controller.advance();
      await controller.idle;
      final second = controller.current!.artwork.entryId;
      expect(second, isNot(first));
      expect(controller.state.recent.first.entryId, second);
      expect(controller.state.recent.map((artwork) => artwork.entryId), containsAll([first, second]));
    });

    test('the fallback skips artworks whose original file is gone', () async {
      final kept = entry(id: 3, dir: tempDir.path);
      final deleted = entry(id: 4, dir: tempDir.path);
      await driftDb.insertEntries({
        for (var id = 1; id <= 2; id++) entry(id: id, dateTaken: id * 10),
        kept,
        deleted,
      });
      await File('${tempDir.path}/3.jpg').writeAsBytes([1]);

      await store.writeState(
        WallpaperState(
          sourceRevision: prefs.scope.revision,
          recent: [
            WallpaperArtwork(entryId: deleted.id, uri: deleted.uri),
            WallpaperArtwork(entryId: kept.id, uri: kept.uri),
          ],
        ),
      );

      await controller.init();
      await controller.idle;
      final fallback = await controller.loadFallbackEntry();
      expect(fallback?.id, kept.id, reason: 'the newest remembered file that still exists wins');
    });

    test('the fallback is empty when nothing survived', () async {
      final deleted = entry(id: 2, dir: tempDir.path);
      await driftDb.insertEntries({entry(id: 1, dir: tempDir.path), deleted});
      await store.writeState(
        WallpaperState(
          sourceRevision: prefs.scope.revision,
          recent: [WallpaperArtwork(entryId: deleted.id, uri: deleted.uri)],
        ),
      );

      await controller.init();
      await controller.idle;
      expect(await controller.loadFallbackEntry(), isNull);
    });
  });
}

class FakeWallpaperBaker extends Fake implements WallpaperBaker {
  final Set<int> failingEntryIds = {};
  final List<int> attemptedEntryIds = [];
  final List<int> effectsHomeBlur = [];
  int bakeCalls = 0;
  int effectsCalls = 0;

  /// Fires [onBake] once, on the bake call with this 1-based number.
  ///
  /// Lets a test land a state change while a bake is in flight.
  int? fireOnBakeCall;
  Future<void> Function()? onBake;

  @override
  Future<WallpaperBake> bake({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
  }) async {
    bakeCalls++;
    attemptedEntryIds.add(entry.id);
    if (bakeCalls == fireOnBakeCall) {
      fireOnBakeCall = null;
      await onBake?.call();
    }
    if (failingEntryIds.contains(entry.id)) {
      throw WallpaperBakeException('test bake failure for ${entry.id}');
    }
    return WallpaperBake(
      size: targetSize,
      darkness: .5,
      sharpPng: Uint8List.fromList([entry.id]),
      effectsHomePng: Uint8List.fromList([entry.id, 1]),
      effectsLockPng: Uint8List.fromList([entry.id, 2]),
    );
  }

  @override
  Future<WallpaperBake> bakeEffects({
    required Uint8List sharpPng,
    required WallpaperEffects home,
    required WallpaperEffects lock,
  }) async {
    effectsCalls++;
    effectsHomeBlur.add(home.blur);
    return WallpaperBake(
      size: const Size(100, 100),
      darkness: .5,
      sharpPng: sharpPng,
      effectsHomePng: Uint8List.fromList([7, 7]),
      effectsLockPng: Uint8List.fromList([8, 8]),
    );
  }
}

class FakeWallpaperBridge extends Fake implements WallpaperBridge {
  bool active = false;
  int reloads = 0;
  int chooserOpens = 0;
  int? autoAdvanceSeconds;

  @override
  Future<bool> isActive() async => active;

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<bool> openChooser() async {
    chooserOpens++;
    return true;
  }

  @override
  Future<Size?> wallpaperSize() async => const Size(100, 100);

  @override
  Future<String?> stateRoot() async => null;

  @override
  Future<void> scheduleAutoAdvance(int seconds) async {
    autoAdvanceSeconds = seconds;
  }
}
