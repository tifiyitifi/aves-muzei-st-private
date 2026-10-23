import 'dart:io';
import 'dart:typed_data';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_state.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const files = WallpaperSlotFiles(
    sharp: 'slots/0/sharp.png',
    effectsHome: 'slots/0/effects_home.png',
    effectsLock: 'slots/0/effects_lock.png',
  );

  const artwork = WallpaperArtwork(
    entryId: 12,
    uri: 'content://media/external/images/media/12',
    title: 'Artwork',
    byline: 'Album',
    attribution: 'Aves',
    dateMillis: 1700000000000,
    files: files,
  );

  const slot = WallpaperSlot(id: 0, artwork: artwork);

  group('WallpaperState', () {
    test('JSON round-trips slots, effects, gestures and target', () {
      const state = WallpaperState(
        generation: 7,
        sourceRevision: 'myPhotos:abc',
        current: 0,
        next: 1,
        slots: [slot],
        effects: WallpaperEffectsConfig(home: WallpaperEffects(blur: 10), link: true),
        gestures: WallpaperGestures(doubleTap: WallpaperTapAction.nextArtwork),
        target: WallpaperTarget.home,
      );

      final decoded = WallpaperState.fromJsonMap(state.toJsonMap());
      expect(decoded, state);
      expect(decoded!.currentSlot?.artwork.entryId, 12);
      expect(decoded.nextSlot, isNull);
      expect(decoded.effects.effectiveLock.blur, 10);
    });

    test('missing/unknown version is rejected', () {
      expect(WallpaperState.fromJsonMap(const {}), isNull);
      expect(WallpaperState.fromJsonMap({'version': 2}), isNull);
    });

    test('invalid and duplicate slots are ignored', () {
      final decoded = WallpaperState.fromJsonMap({
        'version': 1,
        'generation': 1,
        'slots': [
          {'id': 0, 'entryId': 0, 'uri': ''},
          {'id': 1, 'entryId': 12, 'uri': artwork.uri},
          {'id': 1, 'entryId': 13, 'uri': artwork.uri},
        ],
      });
      expect(decoded, isNotNull);
      expect(decoded!.slots, hasLength(1));
      expect(decoded.slots.single.id, 1);
    });

    test('unknown gesture/target names fall back to defaults', () {
      final decoded = WallpaperState.fromJsonMap({
        'version': 1,
        'gestures': {'doubleTap': 'unknown', 'threeFinger': 'nextArtwork'},
        'target': 'unknown',
      });
      expect(decoded!.gestures.doubleTap, WallpaperGestures.defaultDoubleTap);
      expect(decoded.gestures.threeFinger, WallpaperTapAction.nextArtwork);
      expect(decoded.target, WallpaperTarget.homeLock);
    });
  });

  group('WallpaperRuntime', () {
    test('matches only the same generation', () {
      const state = WallpaperState(generation: 3);
      expect(const WallpaperRuntime(generation: 3, current: 0, next: -1).matches(state), isTrue);
      expect(const WallpaperRuntime(generation: 2, current: 0, next: -1).matches(state), isFalse);
    });

    test('JSON round-trips', () {
      const runtime = WallpaperRuntime(generation: 3, current: 0, next: 1, refillRequested: true);
      expect(WallpaperRuntime.fromJsonMap(runtime.toJsonMap()), runtime);
    });

    test('missing generation is rejected', () {
      expect(WallpaperRuntime.fromJsonMap(const {}), isNull);
    });
  });

  group('WallpaperStateStore', () {
    late Directory root;
    late WallpaperStateStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('aves_muzei_wallpaper_test_');
      store = WallpaperStateStore(root);
      await store.ensureLayout();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('writes and reads state atomically', () async {
      const state = WallpaperState(
        generation: 2,
        current: 0,
        slots: [slot],
      );
      await store.writeState(state);

      expect(await store.stateFile.exists(), isTrue);
      expect(await store.tmpDir.list().toList(), isEmpty);
      expect(await store.readState(), state);
      expect(await store.readRuntime(), isNull);
    });

    test('overwrites an existing state without leaving temp files', () async {
      await store.writeState(const WallpaperState(generation: 1));
      await store.writeState(const WallpaperState(generation: 2));

      expect((await store.readState())!.generation, 2);
      expect(await store.tmpDir.list().toList(), isEmpty);
    });

    test('bad JSON falls back to null', () async {
      await store.stateFile.writeAsString('{');
      expect(await store.readState(), isNull);

      await store.runtimeFile.writeAsString('not json');
      expect(await store.readRuntime(), isNull);
    });

    test('writes and reads runtime', () async {
      const runtime = WallpaperRuntime(generation: 4, current: 1, next: 0, refillRequested: true);
      await store.writeRuntime(runtime);
      expect(await store.readRuntime(), runtime);
    });

    test('writes a slot file through the temp directory', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final file = await store.writeSlotBytes(0, WallpaperSlotFiles.sharpName, bytes);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), bytes);
      expect(await store.tmpDir.list().toList(), isEmpty);
    });

    test('writes slot artwork JSON and deletes the slot', () async {
      final file = await store.writeSlotArtwork(0, artwork);
      expect(await file.exists(), isTrue);
      expect(await store.slotDirectory(0).exists(), isTrue);

      await store.deleteSlot(0);
      expect(await store.slotDirectory(0).exists(), isFalse);
    });

    test('clear removes the whole feature directory', () async {
      await store.writeState(const WallpaperState());
      await store.clear();
      expect(await root.exists(), isFalse);
    });
  });
}
