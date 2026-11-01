import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_frame_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedFrameBaker`: which files a frame writes, the native path, and the
/// Dart fallback that every unsupported entry relies on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String photoPath, effectHomePath, effectLockPath;

  setUp(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    dir = await Directory.systemTemp.createTemp('aves_grouped_frame_');
    photoPath = '${dir.path}/frames/1/key/photo.webp';
    effectHomePath = '${dir.path}/frames/1/key/home.png';
    effectLockPath = '${dir.path}/frames/1/key/lock.png';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  AvesEntry entry() => AvesEntry(
        id: 1,
        uri: 'content://frame/1',
        path: '/album/1.png',
        contentId: 1,
        pageId: null,
        sourceMimeType: 'image/png',
        width: 80,
        height: 40,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'frame',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  Future<GroupedFrameBake> bakeWith(GroupedFrameBaker baker, {WallpaperEffects home = const WallpaperEffects(), WallpaperEffects lock = const WallpaperEffects()}) => baker.bakeTo(
        entry: entry(),
        targetSize: const Size(80, 40),
        home: home,
        lock: lock,
        photoPath: photoPath,
        effectHomePath: effectHomePath,
        effectLockPath: effectLockPath,
      );

  group('effect selection', () {
    test('an identity effect writes no effect file', () {
      final effects = groupedFrameEffects(const WallpaperEffects(), const WallpaperEffects());
      expect(effects.home, GroupedFrameEffect.none);
      expect(effects.lock, GroupedFrameEffect.none);
    });

    test('linked surfaces share the home image', () {
      const shared = WallpaperEffects(blur: 250, dim: 128);
      final effects = groupedFrameEffects(shared, shared);
      expect(effects.home, GroupedFrameEffect.home);
      expect(effects.lock, GroupedFrameEffect.home);
    });

    test('different surfaces keep their own images', () {
      final effects = groupedFrameEffects(const WallpaperEffects(blur: 250), const WallpaperEffects(grey: 500));
      expect(effects.home, GroupedFrameEffect.home);
      expect(effects.lock, GroupedFrameEffect.lock);
    });

    test('a sharp home with an effect on the lock only writes the lock image', () {
      final effects = groupedFrameEffects(const WallpaperEffects(), const WallpaperEffects(grey: 500));
      expect(effects.home, GroupedFrameEffect.none);
      expect(effects.lock, GroupedFrameEffect.lock);
    });
  });

  group('SkiaFrameBaker', () {
    test('writes the sharp frame and the effect files it reports', () async {
      final source = await createPng(80, 40);
      final baker = SkiaFrameBaker(GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(source)));

      final bake = await bakeWith(baker, home: const WallpaperEffects(blur: 250), lock: const WallpaperEffects(grey: 500));

      expect(bake.width, 80);
      expect(bake.height, 40);
      expect(bake.homeEffect, GroupedFrameEffect.home);
      expect(bake.lockEffect, GroupedFrameEffect.lock);
      expect(await File(photoPath).exists(), isTrue);
      expect(await File(effectHomePath).exists(), isTrue);
      expect(await File(effectLockPath).exists(), isTrue);
    });

    test('writes no effect file for the identity', () async {
      final source = await createPng(80, 40);
      final baker = SkiaFrameBaker(GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(source)));

      final bake = await bakeWith(baker);

      expect(bake.homeEffect, GroupedFrameEffect.none);
      expect(bake.lockEffect, GroupedFrameEffect.none);
      expect(await File(photoPath).exists(), isTrue);
      expect(await File(effectHomePath).exists(), isFalse);
      expect(await File(effectLockPath).exists(), isFalse);
    });
  });

  group('NativeFrameBaker', () {
    test('measures darkness from the platform sample and keeps the pixels native', () async {
      final source = await createPng(80, 40);
      final platform = _FakePlatform(
        onWrite: (path) async {
          await File(path).parent.create(recursive: true);
          await File(path).writeAsBytes(source);
          return GroupedFrameWriteResult(width: 80, height: 40, thumbnail: Uint8List.fromList(List.filled(64 * 64 * 4, 255)));
        },
      );
      final baker = NativeFrameBaker(platform);

      final bake = await bakeWith(baker);

      expect(bake.width, 80);
      expect(bake.height, 40);
      // Muzei's weights sum to 0.99, so a white sample lands just below 1.
      expect(bake.darkness, closeTo(.986, .01));
      expect(bake.homeEffect, GroupedFrameEffect.none);
      expect(await File(photoPath).exists(), isTrue);
      // The effect math stays in Dart even on the native path.
      expect(await File(effectHomePath).exists(), isFalse);
    });

    test('renders the effects in Dart from the written frame', () async {
      final source = await createPng(80, 40);
      final platform = _FakePlatform(
        onWrite: (path) async {
          await File(path).parent.create(recursive: true);
          await File(path).writeAsBytes(source);
          return GroupedFrameWriteResult(width: 80, height: 40, thumbnail: Uint8List.fromList(List.filled(64 * 64 * 4, 128)));
        },
      );
      final baker = NativeFrameBaker(platform);

      final bake = await bakeWith(baker, home: const WallpaperEffects(blur: 250), lock: const WallpaperEffects(dim: 128));

      expect(bake.homeEffect, GroupedFrameEffect.home);
      expect(bake.lockEffect, GroupedFrameEffect.lock);
      expect(await File(effectHomePath).exists(), isTrue);
      expect(await File(effectLockPath).exists(), isTrue);
    });

    test('falls back to the Dart path when the platform cannot bake', () async {
      final source = await createPng(80, 40);
      final platform = _FakePlatform();
      final baker = NativeFrameBaker(platform, fallback: SkiaFrameBaker(GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(source))));

      final bake = await bakeWith(baker);

      expect(bake.width, 80);
      expect(bake.height, 40);
      expect(await File(photoPath).exists(), isTrue);
    });

    test('keeps videos on the Dart path', () async {
      var writes = 0;
      final platform = _FakePlatform(
        onWrite: (_) async {
          writes++;
          return null;
        },
      );
      final baker = NativeFrameBaker(
        platform,
        fallback: SkiaFrameBaker(GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(Uint8List.fromList([0, 1, 2, 3])))),
      );
      final video = AvesEntry(
        id: 2,
        uri: 'content://frame/2',
        path: null,
        contentId: 2,
        pageId: null,
        sourceMimeType: 'video/mp4',
        width: 80,
        height: 40,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'clip',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 1000,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

      await expectLater(
        baker.bakeTo(
          entry: video,
          targetSize: const Size(80, 40),
          home: const WallpaperEffects(),
          lock: const WallpaperEffects(),
          photoPath: photoPath,
          effectHomePath: effectHomePath,
          effectLockPath: effectLockPath,
        ),
        throwsA(isA<GroupedWallpaperBakeException>()),
      );
      expect(writes, 0);
    });
  });
}

/// A platform whose only real behaviour is [writeFrame].
class _FakePlatform implements GroupedWallpaperPlatform {
  final Future<GroupedFrameWriteResult?> Function(String photoPath)? onWrite;

  new({this.onWrite});

  @override
  Future<GroupedFrameWriteResult?> writeFrame({
    required AvesEntry entry,
    required Size targetSize,
    required String photoPath,
    required int quality,
  }) async =>
      onWrite?.call(photoPath);

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

Future<Uint8List> createPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFF3366CC));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('failed to encode the test image');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
