import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_engine.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_entry_source.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_plan.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperEngine`: the promotion queue, what a run writes, and how
/// every failure degrades to the placeholder instead of a stale image.
void main() {
  const dcimGroup = WallpaperGroup(id: 'group.1', number: 1, name: '@wallpaperGroupDefaultDcim', current: true, updatedAt: 10);
  const plan = GroupedWallpaperPlan(group: dcimGroup);

  late Directory dir;
  late _FakePlatform platform;
  late _FakeBaker baker;
  late _FakePlanStore planStore;
  late _FakeEntrySource entrySource;
  late GroupedWallpaperStateStore store;
  late WallpaperEngineLink link;
  late GroupedWallpaperEngine engine;

  AvesEntry entry(int id) => AvesEntry(
        id: id,
        uri: 'content://media/$id',
        path: null,
        contentId: id,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 300,
        height: 100,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'IMG_$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  /// Newest first, as the entry source returns them.
  GroupedWallpaperEntryWindow window(int n, {int first = 50}) => GroupedWallpaperEntryWindow(
        count: n,
        entries: [for (var i = 0; i < n; i++) entry(first - i)],
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aves_grouped_engine_');
    platform = _FakePlatform(dir.path);
    baker = _FakeBaker();
    planStore = _FakePlanStore(plan);
    entrySource = _FakeEntrySource();
    store = GroupedWallpaperStateStore(dir);
    link = WallpaperEngineLink();
    engine = GroupedWallpaperEngine(
      platform: platform,
      baker: baker,
      planStore: planStore,
      entrySource: entrySource,
      nameResolver: (group) => 'DCIM',
      link: link,
      targetSize: () async => const Size(100, 200),
      now: () => 1234,
    );
    await engine.attach();
  });

  tearDown(() async {
    engine.detach();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('attach wires the platform, the link and the service request', () {
    expect(engine.isAttached, isTrue);
    expect(link.isAttached, isTrue);
    expect(link.isActive, isTrue);
    expect(link.isDisabled, isFalse);
    expect(link.isPlaying, isTrue);
    expect(platform.syncHandler, isNotNull);
  });

  test('a host without the service stays inert', () async {
    final hostless = _FakePlatform(null);
    final hostlessLink = WallpaperEngineLink();
    final hostlessEngine = GroupedWallpaperEngine(platform: hostless, link: hostlessLink);

    await hostlessEngine.attach();

    expect(hostlessEngine.isAttached, isFalse);
    expect(hostlessLink.isAttached, isFalse);
    expect(await hostlessEngine.syncNow(), GroupedWallpaperSyncResult.notActive);
  });

  test('syncNow does nothing while the grouped wallpaper is not the system wallpaper', () async {
    platform.active = false;

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.notActive);
    expect(await store.stateFile.exists(), isFalse);
    expect(baker.bakeCount, 0);
    expect(link.isActive, isFalse);
  });

  group('prepare', () {
    test('bakes a queue before the service is the system wallpaper', () async {
      platform.active = false;
      entrySource.window = window(12);

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      final state = (await store.readState())!;
      expect(state.status, GroupedWallpaperStatus.ready);
      expect(state.groupId, dcimGroup.id);
      expect(state.queueLength, GroupedWallpaperEngine.prefetchAhead + 1);
      expect(state.currentSlot?.entryId, 50);
      expect(state.nextSlot?.entryId, 49);
      expect(state.count, 12);
      expect(state.width, 100);
      expect(state.height, 200);
      for (final slot in state.slots) {
        expect(await store.slotPhotoOf(slot)?.exists(), isTrue);
      }
    });

    test('keeps the queue it already has instead of cycling on every start', () async {
      entrySource.window = window(12);
      await engine.prepare();
      final first = (await store.readState())!;

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect(baker.bakeCount, 3);
      expect((await store.readState())!.current, first.current);
    });

    test('re-bakes when the group range was saved after the bake', () async {
      entrySource.window = window(12);
      await engine.prepare();

      planStore.plan = GroupedWallpaperPlan(
        group: dcimGroup,
        range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, updatedAt: 2000),
      );
      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      expect(baker.bakeCount, 6);
    });

    test('re-bakes when a slot photo is gone from disk', () async {
      entrySource.window = window(12);
      await engine.prepare();
      final state = (await store.readState())!;
      await store.slotPhoto(state.next).delete();

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      expect((await store.readState())!.queueLength, 3);
    });

    test('a small group keeps fewer slots instead of repeating an image', () async {
      entrySource.window = window(2);

      await engine.prepare();

      final state = (await store.readState())!;
      expect(state.queueLength, 2);
      expect(state.slots.map((slot) => slot.entryId).toSet(), {49, 50});
    });

    test('activation with no group adopts the first enabled group', () async {
      planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup.none);
      planStore.adopted = const GroupedWallpaperPlan(group: dcimGroup);
      entrySource.window = window(3, first: 7);

      expect(await engine.prepare(activation: true), GroupedWallpaperSyncResult.baked);

      expect(planStore.adoptCount, 1);
      expect((await store.readState())!.groupId, dcimGroup.id);
    });

    test('a plain prepare does not adopt a group', () async {
      planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup.none);

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect(planStore.adoptCount, 0);
      expect(baker.bakeCount, 0);
    });

    test('activation does not override an explicit off switch', () async {
      planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup.none, disabled: true);

      expect(await engine.prepare(activation: true), GroupedWallpaperSyncResult.disabled);

      expect(planStore.adoptCount, 0);
      expect(baker.bakeCount, 0);
    });
  });

  group('advance', () {
    test('moves to the prefetched slot and refills the queue', () async {
      entrySource.window = window(12);
      await engine.prepare();
      final first = (await store.readState())!;
      expect(first.currentSlot?.entryId, 50);
      expect(first.nextSlot?.entryId, 49);

      expect(await engine.syncNow(), GroupedWallpaperSyncResult.baked);

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 49);
      expect(state.queueLength, 3);
      expect(state.slots.map((slot) => slot.entryId).toSet(), {47, 48, 49});
      // Only the freed slot is baked again: the other two keep their files.
      expect(baker.bakeCount, 4);
    });

    test('a group with a single image keeps showing it', () async {
      entrySource.window = window(1, first: 5);
      await engine.prepare();

      await engine.syncNow();

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 5);
      expect(state.queueLength, 1);
    });

    test('adopts the slot the renderer promoted to', () async {
      entrySource.window = window(12);
      await engine.prepare();
      final first = (await store.readState())!;
      // The renderer promoted `next` on a tap and recorded it.
      await store.runtimeFile.writeAsString(
        '{"generation":${first.generation},"current":${first.next},"next":-1,"refillRequested":true}',
      );

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 49);
      expect(state.queueLength, 3);
    });

    test('a stale runtime is ignored', () async {
      entrySource.window = window(12);
      await engine.prepare();
      final first = (await store.readState())!;
      await store.runtimeFile.writeAsString('{"generation":${first.generation - 1},"current":${first.next},"next":-1}');

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect((await store.readState())!.currentSlot?.entryId, 50);
    });
  });

  group('disabled', () {
    test('keeps the frame on screen and records the status', () async {
      entrySource.window = window(3);
      await engine.prepare();
      final frozen = (await store.readState())!;

      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, disabled: true);
      expect(await engine.prepare(), GroupedWallpaperSyncResult.disabled);

      final state = (await store.readState())!;
      expect(state.status, GroupedWallpaperStatus.disabled);
      expect(state.current, frozen.current);
      expect(state.hasPhoto, isTrue);
      expect(state.generation, frozen.generation + 1);
      expect(baker.bakeCount, 3);
    });

    test('the link reports it is no longer playing', () async {
      await link.setDisabled(true);

      expect(link.isDisabled, isTrue);
      expect(link.isPlaying, isFalse);
      expect(planStore.disabledWrites, [true]);
    });

    test('freezes when the group that was playing disappeared', () async {
      entrySource.window = window(3);
      await engine.prepare();

      // The group was deleted or disabled: normalize leaves no current group.
      planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup.none);
      expect(await engine.prepare(), GroupedWallpaperSyncResult.disabled);

      expect(planStore.disabledWrites, [true]);
      final state = (await store.readState())!;
      expect(state.status, GroupedWallpaperStatus.disabled);
      expect(state.hasPhoto, isTrue);
      expect(baker.bakeCount, 3);
    });
  });

  test('an empty group clears the photos and records the empty state', () async {
    entrySource.window = window(2);
    await engine.prepare();

    entrySource.window = GroupedWallpaperEntryWindow.empty;
    planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup(id: 'group.2', number: 2, name: 'B', current: true, updatedAt: 11));

    expect(await engine.prepare(), GroupedWallpaperSyncResult.empty);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.emptyGroup);
    expect(state.queueLength, 0);
    expect(state.hasPhoto, isFalse);
    expect(await store.slotsDir.exists(), isFalse);
  });

  test('a locked group keeps its queue and bakes nothing', () async {
    entrySource.window = window(12);
    await engine.prepare();
    final frozen = (await store.readState())!;
    final bakes = baker.bakeCount;
    final reloads = platform.reloadCount;

    planStore.plan = GroupedWallpaperPlan(
      group: dcimGroup,
      range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, locked: true),
    );
    expect(await engine.syncNow(), GroupedWallpaperSyncResult.locked);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.locked);
    expect(state.current, frozen.current);
    expect(state.hasPhoto, isTrue);
    expect(baker.bakeCount, bakes);
    expect(platform.reloadCount, reloads);
  });

  test('a locked group with no frame yet writes a placeholder state', () async {
    planStore.plan = GroupedWallpaperPlan(
      group: dcimGroup,
      range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, locked: true),
    );

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.locked);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.locked);
    expect(state.hasPhoto, isFalse);
    expect(state.groupId, dcimGroup.id);
    expect(baker.bakeCount, 0);
  });

  test('a bake failure clears the photos and shows the placeholder', () async {
    entrySource.window = window(4);
    await engine.prepare();
    baker.error = const GroupedWallpaperBakeException('decode failed');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(state.hasPhoto, isFalse);
    expect(await store.slotsDir.exists(), isFalse);
    expect(state.groupId, dcimGroup.id);
  });

  test('a plan read failure still leaves the placeholder, not the old frame', () async {
    entrySource.window = window(2);
    await engine.prepare();
    planStore.error = StateError('database is gone');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(await store.slotsDir.exists(), isFalse);
  });

  test('concurrent runs are serialized instead of writing at the same time', () async {
    entrySource.window = window(4);

    final results = await Future.wait([engine.prepare(), engine.syncNow()]);

    expect(results, [GroupedWallpaperSyncResult.baked, GroupedWallpaperSyncResult.baked]);
    // The last write wins, and the queue never leaves two runs overlapping.
    expect((await store.readState())!.hasPhoto, isTrue);
  });

  test('the service request runs a prepare', () async {
    entrySource.window = window(2, first: 3);
    final reloaded = Completer<void>();
    platform.onReload = () {
      if (!reloaded.isCompleted) reloaded.complete();
    };

    platform.syncHandler!.call();
    await reloaded.future;

    expect((await store.readState())!.hasPhoto, isTrue);
  });

  test('the group range is what the media set is resolved from', () async {
    final range = VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id);
    planStore.plan = GroupedWallpaperPlan(group: dcimGroup, range: range);
    entrySource.window = window(2);

    await engine.syncNow();

    expect(entrySource.lastRange, range);
  });

  group('_pickEntries', () {
    test('skips entries whose file disappeared', () async {
      entrySource.window = GroupedWallpaperEntryWindow(count: 2, entries: [entry(3).copyWith(path: '/gone/3.jpg'), entry(1)]);

      await engine.prepare();

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 1);
    });
  });
}

class _FakePlatform implements GroupedWallpaperPlatform {
  final String? root;
  bool active = true;
  int reloadCount = 0;
  bool chooserOpened = false;
  VoidCallback? syncHandler;
  VoidCallback? onReload;

  new(this.root);

  @override
  Future<bool> isActive() async => active;

  @override
  Future<String?> stateRoot() async => root;

  @override
  Future<Size?> wallpaperSize() async => const Size(100, 200);

  @override
  Future<void> reload() async {
    reloadCount++;
    onReload?.call();
  }

  @override
  Future<bool> openChooser() async {
    chooserOpened = true;
    return true;
  }

  @override
  void setSyncRequestHandler({VoidCallback? onSyncRequested}) {
    syncHandler = onSyncRequested;
  }
}

class _FakeBaker extends GroupedWallpaperBaker {
  int bakeCount = 0;
  AvesEntry? lastEntry;
  Size? lastTarget;
  Object? error;

  @override
  Future<GroupedWallpaperBake> bake({required AvesEntry entry, required Size targetSize}) async {
    bakeCount++;
    lastEntry = entry;
    lastTarget = targetSize;
    final failure = error;
    if (failure != null) throw failure;
    return GroupedWallpaperBake(png: Uint8List.fromList([1, 2, 3]), size: targetSize);
  }
}

class _FakePlanStore implements GroupedWallpaperPlanStore {
  GroupedWallpaperPlan plan;
  GroupedWallpaperPlan adopted;
  Object? error;
  int adoptCount = 0;
  final List<bool> disabledWrites = [];

  new(this.plan) : adopted = plan;

  @override
  Future<GroupedWallpaperPlan> load() async {
    final failure = error;
    if (failure != null) throw failure;
    return plan;
  }

  @override
  Future<GroupedWallpaperPlan> adoptFirstEnabledGroup() async {
    adoptCount++;
    plan = adopted;
    return plan;
  }

  @override
  Future<void> setDisabled(bool disabled) async {
    disabledWrites.add(disabled);
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: disabled);
  }

  @override
  Future<void> setGestures(GroupedWallpaperGestures gestures) async {
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: plan.disabled, gestures: gestures);
  }
}

class _FakeEntrySource implements GroupedWallpaperEntrySource {
  GroupedWallpaperEntryWindow window = GroupedWallpaperEntryWindow.empty;
  VisibleRange? lastRange;

  @override
  Future<GroupedWallpaperEntryWindow> load(VisibleRange? range, {required int limit}) async {
    lastRange = range;
    return window;
  }
}
