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
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_resolution.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_scope.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_state.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_source_repository.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    controller = WallpaperController(
      prefs: prefs,
      repository: WallpaperSourceRepository(database: driftDb, random: Random(7)),
      baker: baker,
      store: store,
      bridge: bridge,
      targetSize: () async => const Size(100, 100),
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
  }) => WallpaperController(
    prefs: prefs,
    repository: WallpaperSourceRepository(database: driftDb, random: Random(7)),
    baker: baker,
    store: store,
    bridge: bridge,
    targetSize: () async => const Size(100, 100),
  );

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
}

class FakeWallpaperBaker extends Fake implements WallpaperBaker {
  final Set<int> failingEntryIds = {};
  final List<int> attemptedEntryIds = [];
  int bakeCalls = 0;
  int effectsCalls = 0;

  @override
  Future<WallpaperBake> bake({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
  }) async {
    bakeCalls++;
    attemptedEntryIds.add(entry.id);
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
}
