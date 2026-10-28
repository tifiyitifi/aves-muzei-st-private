import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperBaker`: target sizing, cover crop, the Muzei-compatible
/// effect pipeline and identity reuse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // MemoryImage keys are the byte array identity; clearing keeps a previous
    // test's decode from satisfying a later one.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  AvesEntry entry({int width = 300, int height = 100}) => AvesEntry(
        id: 1,
        uri: 'content://bake/1',
        path: '/album/1.png',
        contentId: 1,
        pageId: null,
        sourceMimeType: 'image/png',
        width: width,
        height: height,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'bake',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  GroupedWallpaperBaker bakerFor(Uint8List png) => GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(png));

  test('bakes sharp and both effects at the target size', () async {
    final source = await createPng(300, 100, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 300, 100), ui.Paint()..color = const ui.Color(0xFF3366CC)));

    final bake = await bakerFor(source).bake(
      entry: entry(),
      targetSize: const Size(100, 100),
      home: const WallpaperEffects(blur: 10, dim: 20, grey: 30),
      lock: const WallpaperEffects(blur: 40, dim: 50, grey: 60),
    );

    expect(bake.size, const Size(100, 100));
    expect(bake.darkness, inInclusiveRange(0, 1));
    expect(bake.effectsHomePng, isNot(equals(bake.sharpPng)));
    expect(bake.effectsLockPng, isNot(equals(bake.sharpPng)));
    expect(bake.effectsHomePng, isNot(equals(bake.effectsLockPng)));
  });

  test('cover-crops a landscape source around its center', () async {
    // Vertical thirds: red, green, blue. A 100x100 crop of a 300x100 source
    // must take the middle third.
    final source = await createPng(300, 100, (canvas) {
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFFFF0000));
      canvas.drawRect(const ui.Rect.fromLTWH(100, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFF00FF00));
      canvas.drawRect(const ui.Rect.fromLTWH(200, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFF0000FF));
    });
    final bake = await bakerFor(source).bake(
      entry: entry(),
      targetSize: const Size(100, 100),
      home: const WallpaperEffects(),
      lock: const WallpaperEffects(),
    );

    final image = await decodePng(bake.sharpPng);
    try {
      final rgba = await rawRgba(image);
      final (r, g, b) = pixel(rgba, image.width, 50, 50);
      expect(g, greaterThan(200), reason: 'crop should land on the green third');
      expect(r, lessThan(60));
      expect(b, lessThan(60));
    } finally {
      image.dispose();
    }
  });

  test('clamps the target to the GL texture limit and keeps its aspect ratio', () {
    expect(GroupedWallpaperBaker.clampTargetSize(const Size(5000, 2500)), const Size(4096, 2048));
    expect(GroupedWallpaperBaker.clampTargetSize(const Size(2500, 5000)), const Size(2048, 4096));
    expect(GroupedWallpaperBaker.clampTargetSize(const Size(100, 100)), const Size(100, 100));
    expect(() => GroupedWallpaperBaker.clampTargetSize(Size.zero), throwsA(isA<GroupedWallpaperBakeException>()));
  });

  test('greyscale effect desaturates the sharp image', () async {
    final source = await createPng(64, 64, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = const ui.Color(0xFFFF0000)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 64, height: 64),
      targetSize: const Size(64, 64),
      home: const WallpaperEffects(grey: 500),
      lock: const WallpaperEffects(grey: 500),
    );

    final image = await decodePng(bake.effectsHomePng);
    try {
      final rgba = await rawRgba(image);
      final (r, g, b) = pixel(rgba, image.width, 32, 32);
      expect(r, inInclusiveRange(60, 90));
      expect((r - g).abs(), lessThanOrEqualTo(2));
      expect((g - b).abs(), lessThanOrEqualTo(2));
    } finally {
      image.dispose();
    }
  });

  test('dim effect darkens a bright artwork according to its darkness', () async {
    final source = await createPng(64, 64, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = const ui.Color(0xFFFFFFFF)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 64, height: 64),
      targetSize: const Size(64, 64),
      home: const WallpaperEffects(dim: 255),
      lock: const WallpaperEffects(dim: 255),
    );

    expect(bake.darkness, greaterThan(.9));
    final image = await decodePng(bake.effectsHomePng);
    try {
      final rgba = await rawRgba(image);
      final (r, _, _) = pixel(rgba, image.width, 32, 32);
      expect(r, lessThan(10));
    } finally {
      image.dispose();
    }
  });

  test('identity effects reuse the sharp bytes', () async {
    final source = await createPng(40, 40, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 40, 40), ui.Paint()..color = const ui.Color(0xFF808080)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 40, height: 40),
      targetSize: const Size(40, 40),
      home: const WallpaperEffects(),
      lock: const WallpaperEffects(),
    );

    expect(identical(bake.effectsHomePng, bake.sharpPng), isTrue);
    expect(identical(bake.effectsLockPng, bake.sharpPng), isTrue);
  });

  test('linked surfaces bake the same effect bytes', () async {
    final source = await createPng(40, 40, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 40, 40), ui.Paint()..color = const ui.Color(0xFF00FF00)));
    const effects = WallpaperEffects(blur: 10, dim: 20);
    final bake = await bakerFor(source).bake(
      entry: entry(width: 40, height: 40),
      targetSize: const Size(40, 40),
      home: effects,
      lock: effects,
    );

    expect(identical(bake.effectsLockPng, bake.effectsHomePng), isTrue);
  });

  test('decode failures surface as GroupedWallpaperBakeException', () async {
    final baker = GroupedWallpaperBaker(imageProvider: (_) => MemoryImage(Uint8List.fromList([0, 1, 2, 3])));
    await expectLater(
      baker.bake(
        entry: entry(),
        targetSize: const Size(100, 100),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
      ),
      throwsA(isA<GroupedWallpaperBakeException>()),
    );
  });
}

Future<Uint8List> createPng(int width, int height, void Function(ui.Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
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

Future<ui.Image> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> rawRgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('failed to read pixels');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

(int, int, int) pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (rgba[i], rgba[i + 1], rgba[i + 2]);
}
