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
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperEngine`: the promotion queue, the ordering metadata, what a
/// run writes, and how every failure degrades to the placeholder instead of a
/// stale image.
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

  /// Newest first, as the database returns them.
  List<AvesEntry> entries(int n, {int first = 50}) => [for (var i = 0; i < n; i++) entry(first - i)];

  void serve(List<AvesEntry> list, {List<AvesEntry> fresh = const [], int? newest}) {
    entrySource.entries = list;
    entrySource.fresh = fresh;
    entrySource.total = list.length;
    entrySource.newest = newest ?? (list.isEmpty ? 0 : list.first.id);
  }

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
    serve(entries(12));

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.notActive);
    expect(await store.stateFile.exists(), isFalse);
    expect(baker.bakeCount, 0);
    expect(link.isActive, isFalse);
  });

  group('prepare', () {
    test('bakes a queue before the service is the system wallpaper', () async {
      platform.active = false;
      serve(entries(12));

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      final state = (await store.readState())!;
      expect(state.status, GroupedWallpaperStatus.ready);
      expect(state.groupId, dcimGroup.id);
      expect(state.queueLength, GroupedWallpaperEngine.prefetchAhead + 1);
      expect(state.currentSlot?.entryId, 50);
      expect(state.nextSlot?.entryId, 49);
      expect(state.next2Slot?.entryId, 48);
      expect(state.count, 12);
      expect(state.width, 100);
      expect(state.height, 200);
      expect(state.recent.map((entry) => entry.entryId), [50]);
      expect(state.newestEntryId, 50);
      for (final slot in state.slots) {
        expect(await store.slotPhotoOf(slot)?.exists(), isTrue);
      }
    });

    test('keeps the queue it already has instead of cycling on every start', () async {
      serve(entries(12));
      await engine.prepare();
      final first = (await store.readState())!;

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect(baker.bakeCount, 3);
      expect((await store.readState())!.current, first.current);
    });

    test('re-bakes when the group range was saved after the bake', () async {
      serve(entries(12));
      await engine.prepare();

      planStore.plan = GroupedWallpaperPlan(
        group: dcimGroup,
        range: VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id, updatedAt: 2000),
      );
      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      expect(baker.bakeCount, 6);
    });

    test('re-bakes when a slot photo is gone from disk', () async {
      serve(entries(12));
      await engine.prepare();
      final state = (await store.readState())!;
      await store.slotPhoto(state.next).delete();

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      expect((await store.readState())!.queueLength, 3);
    });

    test('re-bakes when a slot effect file is gone from disk', () async {
      baker.distinctEffects = true;
      planStore.plan = GroupedWallpaperPlan(
        group: dcimGroup.copyWith(
          effects: const WallpaperEffectsConfig(
            home: WallpaperEffects(blur: 1),
            lock: WallpaperEffects(blur: 2),
          ),
        ),
      );
      serve(entries(12));
      await engine.prepare();
      final state = (await store.readState())!;
      expect(state.slots.map((slot) => slot.effectHome).toList(), everyElement(isNotEmpty));
      await store.slotPhoto(state.next, name: GroupedWallpaperStateStore.slotEffectHomeFileName).delete();

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      expect((await store.readState())!.queueLength, 3);
    });

    test('a small group keeps fewer slots instead of repeating an image', () async {
      serve(entries(2));

      await engine.prepare();

      final state = (await store.readState())!;
      expect(state.queueLength, 2);
      expect(state.slots.map((slot) => slot.entryId).toSet(), {49, 50});
    });

    test('activation with no group adopts the first enabled group', () async {
      planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup.none);
      planStore.adopted = const GroupedWallpaperPlan(group: dcimGroup);
      serve(entries(3, first: 7));

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

    test('the group range is what the media set is resolved from', () async {
      final range = VisibleRange(id: 'group.1.range', scope: VisibleRangeScope.wallpaper, ownerId: dcimGroup.id);
      planStore.plan = GroupedWallpaperPlan(group: dcimGroup, range: range);
      serve(entries(2));

      await engine.syncNow();

      expect(entrySource.lastRange, range);
    });

    test('bakes the current group effects for both surfaces', () async {
      planStore.plan = GroupedWallpaperPlan(
        group: dcimGroup.copyWith(
          effects: const WallpaperEffectsConfig(
            home: WallpaperEffects(blur: 250),
            lock: WallpaperEffects(grey: 500),
          ),
        ),
      );
      serve(entries(3));

      await engine.prepare();

      expect(baker.lastHome?.blur, 250);
      expect(baker.lastLock?.grey, 500);
    });

    test('identity effects reuse the sharp photo instead of writing a copy', () async {
      serve(entries(3));

      await engine.prepare();

      final state = (await store.readState())!;
      for (final slot in state.slots) {
        expect(slot.effectHome, slot.photo);
        expect(slot.effectLock, slot.photo);
      }
    });

    test('writes home and lock effect files when they differ from the sharp photo', () async {
      baker.distinctEffects = true;
      planStore.plan = GroupedWallpaperPlan(
        group: dcimGroup.copyWith(
          effects: const WallpaperEffectsConfig(
            home: WallpaperEffects(blur: 1),
            lock: WallpaperEffects(blur: 2),
          ),
        ),
      );
      serve(entries(3));

      await engine.prepare();

      final state = (await store.readState())!;
      for (final slot in state.slots) {
        expect(slot.effectHome, endsWith('/home.png'));
        expect(slot.effectLock, endsWith('/lock.png'));
        expect(store.slotEffectPhotoOf(slot, lock: false)?.existsSync(), isTrue);
        expect(store.slotEffectPhotoOf(slot, lock: true)?.existsSync(), isTrue);
      }
    });
  });

  group('ordering', () {
    test('passes the plan ordering and the state metadata to the source', () async {
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, ordering: GroupedWallpaperOrdering.inOrder);
      serve(entries(12));

      await engine.prepare();

      expect(entrySource.lastOrdering, GroupedWallpaperOrdering.inOrder);
      // The marker is seeded from the group before the first pick.
      expect(entrySource.lastNewestEntryId, 50);
      expect((await store.readState())!.ordering, GroupedWallpaperOrdering.inOrder);
    });

    test('new photos are served before the random fallback', () async {
      serve(entries(12), fresh: [entry(60), entry(61)], newest: 50);

      await engine.prepare();

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 60);
      expect(state.nextSlot?.entryId, 61);
      // Nothing new is left: the third slot falls back to random.
      expect(state.next2Slot?.entryId, 50);
    });

    test('a tap keeps advancing through the whole group instead of cycling', () async {
      serve(entries(20));
      await engine.prepare();
      final seen = <int>{};

      for (var i = 0; i < 12; i++) {
        seen.add((await store.readState())!.currentSlot!.entryId);
        expect(await engine.syncNow(), GroupedWallpaperSyncResult.baked);
      }
      seen.add((await store.readState())!.currentSlot!.entryId);

      // A 20-image group with a 3-slot queue must not repeat after the first few.
      expect(seen.length, 13);
      expect(seen, {for (var id = 50; id >= 38; id--) id});
    });

    test('the in-order cursor walks the group and wraps around', () async {
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, ordering: GroupedWallpaperOrdering.inOrder);
      serve(entries(3));
      await engine.prepare();
      expect((await store.readState())!.currentSlot?.entryId, 50);

      await engine.syncNow();
      expect((await store.readState())!.currentSlot?.entryId, 49);

      await engine.syncNow();
      expect((await store.readState())!.currentSlot?.entryId, 48);

      await engine.syncNow();
      expect((await store.readState())!.currentSlot?.entryId, 50);
    });
  });

  group('advance', () {
    test('moves to the prefetched slot and refills the queue', () async {
      serve(entries(12));
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
      expect(state.recent.map((entry) => entry.entryId), [49, 50]);
    });

    test('a group with a single image keeps showing it', () async {
      serve(entries(1, first: 5));
      await engine.prepare();

      await engine.syncNow();

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 5);
      expect(state.queueLength, 1);
    });

    test('adopts the slot the renderer promoted to', () async {
      serve(entries(12));
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

    test('adopts a promotion made while the queue was baking', () async {
      serve(entries(12));
      await engine.prepare();
      final first = (await store.readState())!;
      // The renderer promoted once before this run...
      await store.runtimeFile.writeAsString(
        '{"generation":${first.generation},"current":${first.next},"next":${first.next2},"refillRequested":true}',
      );
      // ...and once more while Dart bakes the freed slot.
      baker.onBake = () => store.runtimeFile.writeAsString(
        '{"generation":${first.generation},"current":${first.next2},"next":-1,"refillRequested":true}',
      );

      expect(await engine.prepare(), GroupedWallpaperSyncResult.baked);

      final state = (await store.readState())!;
      expect(state.currentSlot?.entryId, 48);
      expect(state.nextSlot?.entryId, 47);
      expect(state.next2, -1);
      // Both photos the renderer showed are kept out of the next picks.
      expect(state.recent.map((entry) => entry.entryId), [48, 49, 50]);
    });

    test('a runtime pointing at the current slot is not a promotion', () async {
      serve(entries(12));
      await engine.prepare();
      final first = (await store.readState())!;
      await store.runtimeFile.writeAsString('{"generation":${first.generation},"current":${first.current},"next":-1}');

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect((await store.readState())!.currentSlot?.entryId, 50);
    });

    test('a stale runtime is ignored', () async {
      serve(entries(12));
      await engine.prepare();
      final first = (await store.readState())!;
      await store.runtimeFile.writeAsString('{"generation":${first.generation - 1},"current":${first.next},"next":-1}');

      expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);

      expect((await store.readState())!.currentSlot?.entryId, 50);
    });
  });

  group('disabled', () {
    test('keeps the frame on screen and records the status', () async {
      serve(entries(3));
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
      serve(entries(3));
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
    serve(entries(2));
    await engine.prepare();

    serve(const []);
    planStore.plan = const GroupedWallpaperPlan(group: WallpaperGroup(id: 'group.2', number: 2, name: 'B', current: true, updatedAt: 11));

    expect(await engine.prepare(), GroupedWallpaperSyncResult.empty);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.emptyGroup);
    expect(state.queueLength, 0);
    expect(state.hasPhoto, isFalse);
    expect(await store.slotsDir.exists(), isFalse);
  });

  test('a locked group keeps its queue and bakes nothing', () async {
    serve(entries(12));
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

  test('a bake failure while filling the queue keeps the frame and the queue', () async {
    serve(entries(12));
    await engine.prepare();
    baker.error = const GroupedWallpaperBakeException('decode failed');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.baked);

    final state = (await store.readState())!;
    expect(state.currentSlot?.entryId, 49);
    expect(state.nextSlot?.entryId, 48);
    // The freed slot stays empty rather than showing a broken photo.
    expect(state.next2, -1);
  });

  test('a bake failure on the first frame clears the photos and shows the placeholder', () async {
    serve(entries(4));
    baker.error = const GroupedWallpaperBakeException('decode failed');

    expect(await engine.prepare(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(state.hasPhoto, isFalse);
    expect(await store.slotsDir.exists(), isFalse);
    expect(state.groupId, dcimGroup.id);
  });

  test('a plan read failure still leaves the placeholder, not the old frame', () async {
    serve(entries(2));
    await engine.prepare();
    planStore.error = StateError('database is gone');

    expect(await engine.syncNow(), GroupedWallpaperSyncResult.failed);

    final state = (await store.readState())!;
    expect(state.status, GroupedWallpaperStatus.unavailable);
    expect(await store.slotsDir.exists(), isFalse);
  });

  test('concurrent runs are serialized instead of writing at the same time', () async {
    serve(entries(4));

    final results = await Future.wait([engine.prepare(), engine.syncNow()]);

    expect(results, [GroupedWallpaperSyncResult.baked, GroupedWallpaperSyncResult.baked]);
    // The last write wins, and the queue never leaves two runs overlapping.
    expect((await store.readState())!.hasPhoto, isTrue);
  });

  test('the service request runs a prepare', () async {
    serve(entries(2, first: 3));
    final reloaded = Completer<void>();
    platform.onReload = () {
      if (!reloaded.isCompleted) reloaded.complete();
    };

    platform.syncHandler!();
    await reloaded.future;

    expect((await store.readState())!.hasPhoto, isTrue);
  });

  test('a group with a missing file skips it instead of baking a broken photo', () async {
    serve([entry(3).copyWith(path: '/gone/3.jpg'), entry(1)]);

    await engine.prepare();

    final state = (await store.readState())!;
    expect(state.currentSlot?.entryId, 1);
  });

  test('pausing writes the flag without baking and survives a refill', () async {
    serve(entries(12));
    await engine.prepare();
    final bakes = baker.bakeCount;

    await engine.setPaused(true);

    final paused = (await store.readState())!;
    expect(paused.paused, isTrue);
    expect(baker.bakeCount, bakes);
    expect(planStore.pausedWrites, [true]);

    expect(await engine.prepare(), GroupedWallpaperSyncResult.unchanged);
    expect((await store.readState())!.paused, isTrue);
  });

  test('resuming writes the flag back', () async {
    serve(entries(12));
    await engine.prepare();
    await engine.setPaused(true);

    await engine.setPaused(false);

    expect((await store.readState())!.paused, isFalse);
    expect(planStore.pausedWrites, [true, false]);
  });

  test('turning the notification off reaches the state and refreshes the bar', () async {
    serve(entries(12));
    await engine.prepare();
    final bakes = baker.bakeCount;

    await engine.setNotification(false);

    expect((await store.readState())!.notification, isFalse);
    expect(planStore.notificationWrites, [false]);
    expect(platform.notificationRefreshes, 1);
    // The frame on screen does not change, so nothing is re-baked.
    expect(baker.bakeCount, bakes);

    await engine.setNotification(true);

    expect((await store.readState())!.notification, isTrue);
    expect(platform.notificationRefreshes, 2);
  });

  test('a bake keeps the notification switch of the plan', () async {
    serve(entries(12));
    planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, notification: false);

    await engine.prepare();

    expect((await store.readState())!.notification, isFalse);
  });

  test('switching group makes the new group current and re-bakes', () async {
    serve(entries(12));
    await engine.prepare();
    const nextGroup = WallpaperGroup(id: 'group.2', number: 2, name: '@wallpaperGroupDefaultPictures', current: true, updatedAt: 20);
    planStore.switched = const GroupedWallpaperPlan(group: nextGroup);

    expect(await engine.switchGroup(1), GroupedWallpaperSyncResult.baked);

    final state = (await store.readState())!;
    expect(state.groupId, 'group.2');
    expect(state.status, GroupedWallpaperStatus.ready);
    expect(planStore.switchDeltas, [1]);
  });

  test('switching to a locked group still displays it', () async {
    serve(entries(4));
    await engine.prepare();
    const nextGroup = WallpaperGroup(id: 'group.2', number: 2, name: '@wallpaperGroupDefaultPictures', current: true, updatedAt: 20);
    planStore.switched = const GroupedWallpaperPlan(
      group: nextGroup,
      range: VisibleRange(id: 'group.2.range', scope: VisibleRangeScope.wallpaper, ownerId: 'group.2', locked: true),
    );

    expect(await engine.switchGroup(1), GroupedWallpaperSyncResult.baked);

    final state = (await store.readState())!;
    expect(state.groupId, 'group.2');
    expect(state.status, GroupedWallpaperStatus.ready);
    expect(state.hasPhoto, isTrue);
  });

  test('previous photo re-bakes the last shown photo and queues the current after it', () async {
    serve(entries(12));
    await engine.prepare();
    // One forward step: 50 → 49, so 50 becomes the previous photo.
    await engine.syncNow();
    final advanced = (await store.readState())!;
    expect(advanced.currentSlot?.entryId, 49);

    expect(await engine.previousArtwork(), GroupedWallpaperSyncResult.baked);

    final state = (await store.readState())!;
    expect(state.currentSlot?.entryId, 50);
    expect(state.nextSlot?.entryId, 49);
    expect(state.next2Slot, isNotNull);
    expect(state.queueLength, 3);
    expect(state.recent.first.entryId, 50);
    for (final slot in state.slots) {
      expect(store.slotPhotoOf(slot)?.existsSync(), isTrue);
    }
  });

  test('previous photo without history is a no-op', () async {
    serve(entries(12));
    await engine.prepare();
    final before = (await store.readState())!;

    expect(await engine.previousArtwork(), GroupedWallpaperSyncResult.unchanged);

    final after = (await store.readState())!;
    expect(after.generation, before.generation);
    expect(after.current, before.current);
  });

  test('previous photo skips a photo that left the media set', () async {
    serve(entries(12));
    await engine.prepare();
    await engine.syncNow();
    // The previous photo (50) is now hidden, e.g. by a locked vault.
    entrySource.entries = entries(12).where((entry) => entry.id != 50).toList();

    expect(await engine.previousArtwork(), GroupedWallpaperSyncResult.unchanged);

    expect((await store.readState())!.currentSlot?.entryId, 49);
  });

  test('previous photo does not cross into another group history', () async {
    serve(entries(12));
    await engine.prepare();
    final state = (await store.readState())!;
    await store.writeState(state.copyWith(
      recent: [
        const GroupedWallpaperRecentEntry(entryId: 50, groupId: 'group.1'),
        const GroupedWallpaperRecentEntry(entryId: 49, groupId: 'group.2'),
      ],
    ));

    expect(await engine.previousArtwork(), GroupedWallpaperSyncResult.unchanged);
  });

  test('a v3 history entry with no group id still counts as this group', () async {
    serve(entries(12));
    await engine.prepare();
    final state = (await store.readState())!;
    await store.writeState(state.copyWith(
      recent: [
        GroupedWallpaperRecentEntry(entryId: state.entryId!),
        const GroupedWallpaperRecentEntry(entryId: 49),
      ],
    ));

    expect(await engine.previousArtwork(), GroupedWallpaperSyncResult.baked);

    expect((await store.readState())!.currentSlot?.entryId, 49);
  });

  test('a notification command pauses and resumes the wallpaper', () async {
    serve(entries(2));
    await engine.prepare();

    await engine.handleCommand('pause');
    expect((await store.readState())!.paused, isTrue);

    await engine.handleCommand('resume');
    expect((await store.readState())!.paused, isFalse);
  });

  test('an unknown notification command is ignored', () async {
    serve(entries(2));
    await engine.prepare();

    await engine.handleCommand('deleteEverything');

    expect((await store.readState())!.hasPhoto, isTrue);
  });

  test('attach wires the notification command handler', () {
    expect(platform.commandHandler, isNotNull);
  });

  group('auto-advance', () {
    test('prepare applies the current group interval to the scheduler', () async {
      serve(entries(12));
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, interval: WallpaperInterval.m15);

      await engine.prepare();

      expect(platform.scheduledSeconds.last, WallpaperInterval.m15.seconds);
    });

    test('a frozen wallpaper schedules no auto-advance', () async {
      serve(entries(12));
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, interval: WallpaperInterval.h1, paused: true);

      await engine.prepare();

      expect(platform.scheduledSeconds.last, 0);
    });

    test('freezing cancels the interval and resuming restarts it', () async {
      serve(entries(12));
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, interval: WallpaperInterval.m30);
      await engine.prepare();
      expect(platform.scheduledSeconds.last, WallpaperInterval.m30.seconds);

      await engine.handleCommand('pause');
      expect(platform.scheduledSeconds.last, 0);

      await engine.handleCommand('resume');
      expect(platform.scheduledSeconds.last, WallpaperInterval.m30.seconds);
    });

    test('an interval run keeps the photo while the wallpaper is frozen', () async {
      serve(entries(12));
      await engine.prepare();
      final before = (await store.readState())!;
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, paused: true);

      expect(await engine.refill(advance: true), GroupedWallpaperSyncResult.unchanged);

      final after = (await store.readState())!;
      expect(after.entryId, before.entryId);
      expect(after.current, before.current);
    });

    test('refreshSchedule re-applies an edited interval without baking', () async {
      serve(entries(12));
      await engine.prepare();
      final bakeCount = baker.bakeCount;
      planStore.plan = const GroupedWallpaperPlan(group: dcimGroup, interval: WallpaperInterval.h6);

      await engine.refreshSchedule();

      expect(platform.scheduledSeconds.last, WallpaperInterval.h6.seconds);
      expect(baker.bakeCount, bakeCount);
    });
  });
}

class _FakePlatform implements GroupedWallpaperPlatform {
  final String? root;
  bool active = true;
  int reloadCount = 0;
  bool chooserOpened = false;
  final List<int> scheduledSeconds = [];
  void Function()? syncHandler;
  void Function(String command)? commandHandler;
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
  Future<void> scheduleAutoAdvance(int seconds) async {
    scheduledSeconds.add(seconds);
  }

  @override
  Future<void> refreshNotification() async {
    notificationRefreshes++;
  }

  int notificationRefreshes = 0;

  @override
  Future<bool> openChooser() async {
    chooserOpened = true;
    return true;
  }

  @override
  void setSyncRequestHandler({void Function()? onSyncRequested, void Function(String command)? onCommand}) {
    syncHandler = onSyncRequested;
    commandHandler = onCommand;
  }
}

class _FakeBaker extends GroupedWallpaperBaker {
  int bakeCount = 0;
  AvesEntry? lastEntry;
  Size? lastTarget;
  WallpaperEffects? lastHome;
  WallpaperEffects? lastLock;
  Object? error;

  /// Returns distinct bytes for each surface, so a test can assert the effect
  /// files are written.
  bool distinctEffects = false;

  /// Runs during a bake, so a test can simulate a promotion mid-run.
  Future<void> Function()? onBake;

  @override
  Future<GroupedWallpaperBake> bake({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
  }) async {
    bakeCount++;
    lastEntry = entry;
    lastTarget = targetSize;
    lastHome = home;
    lastLock = lock;
    await onBake?.call();
    final failure = error;
    if (failure != null) throw failure;
    final sharp = Uint8List.fromList([1, 2, 3]);
    return GroupedWallpaperBake(
      sharpPng: sharp,
      effectsHomePng: distinctEffects ? Uint8List.fromList([4, 5, 6]) : sharp,
      effectsLockPng: distinctEffects ? Uint8List.fromList([7, 8, 9]) : sharp,
      size: targetSize,
      darkness: .5,
    );
  }
}

class _FakePlanStore implements GroupedWallpaperPlanStore {
  GroupedWallpaperPlan plan;
  GroupedWallpaperPlan adopted;

  /// The plan returned by [switchGroup]; null keeps the current plan.
  GroupedWallpaperPlan? switched;
  Object? error;
  int adoptCount = 0;
  final List<bool> disabledWrites = [];
  final List<bool> pausedWrites = [];
  final List<int> switchDeltas = [];

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
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: disabled, gestures: plan.gestures, ordering: plan.ordering, interval: plan.interval, paused: plan.paused, notification: plan.notification);
  }

  @override
  Future<void> setGestures(GroupedWallpaperGestures gestures) async {
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: plan.disabled, gestures: gestures, ordering: plan.ordering, interval: plan.interval, paused: plan.paused, notification: plan.notification);
  }

  @override
  Future<void> setPaused(bool paused) async {
    pausedWrites.add(paused);
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: plan.disabled, gestures: plan.gestures, ordering: plan.ordering, interval: plan.interval, paused: paused, notification: plan.notification);
  }

  @override
  Future<void> setNotification(bool enabled) async {
    notificationWrites.add(enabled);
    plan = GroupedWallpaperPlan(group: plan.group, range: plan.range, disabled: plan.disabled, gestures: plan.gestures, ordering: plan.ordering, interval: plan.interval, paused: plan.paused, notification: enabled);
  }

  final List<bool> notificationWrites = [];

  @override
  Future<GroupedWallpaperPlan> switchGroup(int delta) async {
    switchDeltas.add(delta);
    final target = switched;
    if (target == null) return plan;
    plan = target;
    return plan;
  }
}

/// A deterministic stand-in for the database-backed source.
///
/// It mirrors the three orderings without SQL: `inOrder` walks [entries],
/// `newThenRandom` serves [fresh] first, and `random` walks the not-yet-shown
/// entries in list order. That is enough to assert how the engine drives it.
class _FakeEntrySource implements GroupedWallpaperEntrySource {
  List<AvesEntry> entries = const [];
  List<AvesEntry> fresh = const [];
  int total = 0;
  int newest = 0;

  VisibleRange? lastRange;
  GroupedWallpaperOrdering? lastOrdering;
  int? lastNewestEntryId;

  @override
  Future<int> count(VisibleRange? range) async => total;

  @override
  Future<int> newPhotoMarker(VisibleRange? range) async => newest;

  @override
  Future<GroupedWallpaperPick> pick(
    VisibleRange? range, {
    required GroupedWallpaperOrdering ordering,
    required int cursor,
    int attempt = 0,
    int newestEntryId = 0,
    Set<int> excludeEntryIds = const {},
  }) async {
    lastRange = range;
    lastOrdering = ordering;
    lastNewestEntryId = newestEntryId;

    bool usable(AvesEntry entry) => !entry.isMissingAtPath && !excludeEntryIds.contains(entry.id);

    if (ordering == GroupedWallpaperOrdering.newThenRandom) {
      final candidates = fresh.where(usable).toList();
      if (attempt < candidates.length) {
        return GroupedWallpaperPick(entry: candidates[attempt], total: total);
      }
    }
    if (ordering == GroupedWallpaperOrdering.inOrder) {
      if (entries.isEmpty) return GroupedWallpaperPick(total: total);
      final offset = (cursor + attempt) % entries.length;
      return GroupedWallpaperPick(entry: entries[offset], total: total, offset: offset);
    }
    final candidates = entries.where(usable).toList();
    if (candidates.isEmpty) return GroupedWallpaperPick(total: total);
    final pick = candidates[attempt % candidates.length];
    return GroupedWallpaperPick(entry: pick, total: total, offset: entries.indexOf(pick));
  }

  @override
  Future<AvesEntry?> entryById(VisibleRange? range, int id) async {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
