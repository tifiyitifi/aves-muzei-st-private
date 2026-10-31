import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperStateStore`: the shared directory, atomic writes, the slot
/// photos and the tolerance that keeps the wallpaper service alive when a file
/// is broken.
void main() {
  late Directory dir;
  late GroupedWallpaperStateStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aves_grouped_store_');
    store = GroupedWallpaperStateStore(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  const state = GroupedWallpaperState(
    generation: 2,
    status: GroupedWallpaperStatus.ready,
    groupId: 'group.1',
    groupNumber: 1,
    groupName: 'All',
    count: 5,
    current: 0,
    next: 1,
    slots: [
      GroupedWallpaperSlot(id: 0, entryId: 9, uri: 'content://9', title: 'IMG_9', photo: 'slots/0/photo.png', width: 100, height: 200),
      GroupedWallpaperSlot(id: 1, entryId: 10, uri: 'content://10', title: 'IMG_10', photo: 'slots/1/photo.png', width: 100, height: 200),
    ],
    bakedAt: 7,
  );

  test('a missing state file reads as no state', () async {
    expect(await store.readState(), isNull);
    expect(await store.readRuntime(), isNull);
  });

  test('writes and reads the state atomically', () async {
    await store.writeState(state);

    expect(await store.readState(), state);
    expect(await store.stateFile.exists(), isTrue);
    // The staging file is renamed over the destination, never left behind.
    expect(await store.tmpDir.list().toList(), isEmpty);
  });

  test('a truncated or foreign state file reads as no state', () async {
    await store.ensureLayout();
    await store.stateFile.writeAsString('{"version": 2, "status": "rea');
    expect(await store.readState(), isNull);

    await store.stateFile.writeAsString('[1, 2, 3]');
    expect(await store.readState(), isNull);

    await store.stateFile.writeAsString('');
    expect(await store.readState(), isNull);
  });

  test('writes a frame under its entry id, not its slot id', () async {
    final photo = await store.writeFramePhoto(42, '100x200-abcd', Uint8List.fromList([1, 2, 3]));

    expect(photo, 'frames/42/100x200-abcd/photo.png');
    expect(await store.frameFile(42, '100x200-abcd', GroupedWallpaperStateStore.slotPhotoFileName).readAsBytes(), [1, 2, 3]);
  });

  test('writes home and lock effect photos next to the sharp one', () async {
    const key = '100x200-abcd';
    final sharp = await store.writeFramePhoto(42, key, Uint8List.fromList([1]));
    final home = await store.writeFramePhoto(42, key, Uint8List.fromList([2]), name: GroupedWallpaperStateStore.slotEffectHomeFileName);
    final lock = await store.writeFramePhoto(42, key, Uint8List.fromList([3]), name: GroupedWallpaperStateStore.slotEffectLockFileName);

    expect(home, 'frames/42/$key/home.png');
    expect(lock, 'frames/42/$key/lock.png');
    final slot = GroupedWallpaperSlot(id: 3, entryId: 42, uri: '', photo: sharp, effectHome: home, effectLock: lock);
    expect(store.slotEffectPhotoOf(slot, lock: false)?.readAsBytesSync(), [2]);
    expect(store.slotEffectPhotoOf(slot, lock: true)?.readAsBytesSync(), [3]);
  });

  test('an identity or missing effect falls back to the sharp photo', () async {
    const key = '100x200-abcd';
    final sharp = await store.writeFramePhoto(42, key, Uint8List.fromList([1]));
    final identity = GroupedWallpaperSlot(id: 3, entryId: 42, uri: '', photo: sharp);
    expect(store.slotEffectPhotoOf(identity, lock: false)?.path, store.frameFile(42, key, GroupedWallpaperStateStore.slotPhotoFileName).path);
    expect(store.slotEffectPhotoOf(identity, lock: true)?.path, store.frameFile(42, key, GroupedWallpaperStateStore.slotPhotoFileName).path);

    final missing = GroupedWallpaperSlot(id: 3, entryId: 42, uri: '', photo: sharp, effectHome: 'frames/42/$key/gone.png');
    expect(store.slotEffectPhotoOf(missing, lock: false)?.path, store.frameFile(42, key, GroupedWallpaperStateStore.slotPhotoFileName).path);
  });

  test('a cached frame is read back with its metadata', () async {
    const key = '100x200-abcd';
    await store.writeFramePhoto(42, key, Uint8List.fromList([1]));
    await store.writeFrameMeta(42, key, width: 100, height: 200, darkness: 0.25, title: 'IMG_42', uri: 'content://42');

    final frame = store.cachedFrame(42, key)!;
    expect(frame.photo, 'frames/42/$key/photo.png');
    expect(frame.effectHome, isEmpty);
    expect(frame.width, 100);
    expect(frame.height, 200);
    expect(frame.darkness, 0.25);
  });

  test('another layout key misses the cache', () async {
    await store.writeFramePhoto(42, '100x200-abcd', Uint8List.fromList([1]));
    await store.writeFrameMeta(42, '100x200-abcd', width: 100, height: 200, darkness: 0.5, title: '', uri: '');

    expect(store.cachedFrame(42, '100x200-abcd'), isNotNull);
    expect(store.cachedFrame(42, '300x200-abcd'), isNull);
    expect(store.cachedFrame(42, '100x200-eeff'), isNull);
  });

  test('pruning keeps the referenced frames and drops the oldest', () async {
    for (var entryId = 1; entryId <= 4; entryId++) {
      await store.writeFramePhoto(entryId, '100x200-k', Uint8List.fromList([entryId]));
      await store.writeFrameMeta(entryId, '100x200-k', width: 100, height: 200, darkness: 0.5, title: '', uri: '');
      // Distinct ages, so the eviction order is deterministic.
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    // Entry 1 is the one on screen: it must survive even as the oldest.
    await store.pruneFrames(keep: {'frames/1/100x200-k/photo.png'}, maxFrames: 2);

    expect(await store.frameFile(1, '100x200-k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isTrue);
    expect(await store.frameFile(4, '100x200-k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isTrue);
    expect(await store.frameFile(2, '100x200-k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isFalse);
    expect(await store.frameFile(3, '100x200-k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isFalse);
  });

  test('clearing the history drops every unreferenced frame', () async {
    await store.writeFramePhoto(1, 'k', Uint8List.fromList([1]));
    await store.writeFramePhoto(2, 'k', Uint8List.fromList([2]));
    final legacy = File('${dir.path}/${GroupedWallpaperState.photoFileNameV1}');
    await legacy.writeAsBytes([9]);

    await store.clearFrames(keep: {'frames/1/k/photo.png'});

    expect(await store.frameFile(1, 'k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isTrue);
    expect(await store.frameFile(2, 'k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isFalse);
    expect(await legacy.exists(), isTrue);

    await store.clearSlots();

    expect(await store.frameFile(1, 'k', GroupedWallpaperStateStore.slotPhotoFileName).exists(), isFalse);
    expect(await legacy.exists(), isFalse);
    // Clearing a frame that is already gone is not an error.
    await store.clearSlots();
  });

  test('a rewrite replaces the previous file instead of appending', () async {
    await store.writeFramePhoto(42, 'k', Uint8List.fromList([1, 2, 3, 4]));
    await store.writeFramePhoto(42, 'k', Uint8List.fromList([9]));
    expect(await store.frameFile(42, 'k', GroupedWallpaperStateStore.slotPhotoFileName).readAsBytes(), [9]);

    await store.writeState(state);
    await store.writeState(state.copyWith(generation: 3));
    expect((await store.readState())!.generation, 3);
  });

  test('the notification switch travels with the state', () async {
    await store.writeState(state.copyWith(notification: false));
    expect((await store.readState())!.notification, isFalse);

    await store.writeState(state.copyWith(notification: true));
    expect((await store.readState())!.notification, isTrue);
  });

  test('a state written before the switch existed reads as notification on', () async {
    await store.ensureLayout();
    // The field is absent, which is what every build before the switch wrote.
    await store.stateFile.writeAsString('{"version": 4, "status": "ready", "groupId": "g", "current": -1}');
    final state = (await store.readState())!;
    expect(state.notification, isTrue);
    // An unknown layout re-bakes once instead of keeping a stale texture.
    expect(state.surfaceWidth, 0);
    expect(state.surfaceHeight, 0);
    expect(state.scrollEffect, isFalse);
  });

  test('the baked layout travels with the state', () async {
    await store.writeState(state.copyWith(surfaceWidth: 1080, surfaceHeight: 2340, scrollEffect: true));

    final read = (await store.readState())!;
    expect(read.surfaceWidth, 1080);
    expect(read.surfaceHeight, 2340);
    expect(read.scrollEffect, isTrue);
  });

  test('reads the runtime the renderer wrote', () async {
    await store.ensureLayout();
    await store.runtimeFile.writeAsString('{"generation":2,"current":1,"next":-1,"refillRequested":true}');

    final runtime = (await store.readRuntime())!;

    expect(runtime.generation, 2);
    expect(runtime.current, 1);
    expect(runtime.next, -1);
    expect(runtime.refillRequested, isTrue);
  });

  test('a missing lock request reads as none', () async {
    expect(await store.readLockRequest(), isNull);
  });

  test('the lock request names its group until it is cleared', () async {
    await store.ensureLayout();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Written by the native side: the app was not listening when the bar was
    // tapped, so the group has to survive until it is started.
    await store.lockRequestFile.writeAsString('{"groupId":"group.2","at":$now}');

    expect(await store.readLockRequest(nowMillis: now), 'group.2');

    await store.clearLockRequest();

    expect(await store.readLockRequest(nowMillis: now), isNull);
  });

  test('a stale lock request is ignored', () async {
    await store.ensureLayout();
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = now - GroupedWallpaperStateStore.lockRequestMaxAge.inMilliseconds - 1;
    await store.lockRequestFile.writeAsString('{"groupId":"group.2","at":$stale}');

    expect(await store.readLockRequest(nowMillis: now), isNull);
  });

  test('a broken lock request reads as none', () async {
    await store.ensureLayout();
    await store.lockRequestFile.writeAsString('{"groupId":');

    expect(await store.readLockRequest(), isNull);
  });

  test('a lock request without a group is ignored', () async {
    await store.ensureLayout();
    await store.lockRequestFile.writeAsString('{"groupId":""}');

    expect(await store.readLockRequest(), isNull);
  });
}
