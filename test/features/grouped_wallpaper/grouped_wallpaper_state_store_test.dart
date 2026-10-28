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

  test('writes one photo per slot', () async {
    final photo = await store.writeSlotPhoto(3, Uint8List.fromList([1, 2, 3]));

    expect(photo, 'slots/3/photo.png');
    expect(await store.slotPhoto(3).readAsBytes(), [1, 2, 3]);
  });

  test('pruning drops the slots that left the queue', () async {
    await store.writeSlotPhoto(0, Uint8List.fromList([1]));
    await store.writeSlotPhoto(1, Uint8List.fromList([2]));
    await store.writeSlotPhoto(2, Uint8List.fromList([3]));

    await store.pruneSlots({0, 2});

    expect(await store.slotPhoto(0).exists(), isTrue);
    expect(await store.slotPhoto(1).exists(), isFalse);
    expect(await store.slotPhoto(2).exists(), isTrue);
  });

  test('clearing removes every photo and the legacy one', () async {
    await store.writeSlotPhoto(0, Uint8List.fromList([1]));
    final legacy = File('${dir.path}/${GroupedWallpaperState.photoFileNameV1}');
    await legacy.writeAsBytes([9]);

    await store.clearSlots();

    expect(await store.slotPhoto(0).exists(), isFalse);
    expect(await legacy.exists(), isFalse);
    // Clearing a photo that is already gone is not an error.
    await store.clearSlots();
  });

  test('a rewrite replaces the previous file instead of appending', () async {
    await store.writeSlotPhoto(0, Uint8List.fromList([1, 2, 3, 4]));
    await store.writeSlotPhoto(0, Uint8List.fromList([9]));
    expect(await store.slotPhoto(0).readAsBytes(), [9]);

    await store.writeState(state);
    await store.writeState(state.copyWith(generation: 3));
    expect((await store.readState())!.generation, 3);
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
}
