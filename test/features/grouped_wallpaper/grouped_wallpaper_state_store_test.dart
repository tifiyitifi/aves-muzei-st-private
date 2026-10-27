import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperStateStore`: the shared directory, atomic writes and the
/// tolerance that keeps the wallpaper service alive when a file is broken.
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
    entryId: 9,
    entryTitle: 'IMG_9',
    photo: GroupedWallpaperState.photoFileName,
    width: 100,
    height: 200,
    bakedAt: 7,
  );

  test('a missing state file reads as no state', () async {
    expect(await store.readState(), isNull);
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
    await store.stateFile.writeAsString('{"version": 1, "status": "rea');
    expect(await store.readState(), isNull);

    await store.stateFile.writeAsString('[1, 2, 3]');
    expect(await store.readState(), isNull);

    await store.stateFile.writeAsString('');
    expect(await store.readState(), isNull);
  });

  test('writes and clears the photo', () async {
    await store.writePhoto(Uint8List.fromList([1, 2, 3]));
    expect(await store.photoFile.exists(), isTrue);
    expect(await store.photoFile.readAsBytes(), [1, 2, 3]);

    await store.clearPhoto();
    expect(await store.photoFile.exists(), isFalse);
    // Clearing a photo that is already gone is not an error.
    await store.clearPhoto();
  });

  test('a rewrite replaces the previous file instead of appending', () async {
    await store.writePhoto(Uint8List.fromList([1, 2, 3, 4]));
    await store.writePhoto(Uint8List.fromList([9]));
    expect(await store.photoFile.readAsBytes(), [9]);

    await store.writeState(state);
    await store.writeState(state.copyWith(generation: 3));
    expect((await store.readState())!.generation, 3);
  });
}
