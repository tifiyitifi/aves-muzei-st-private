import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_baker.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_frame_geometry.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
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

  test('a blurred effect is baked at a quarter of the frame', () async {
    final source = await createPng(80, 40, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 80, 40), ui.Paint()..color = const ui.Color(0xFF3366CC)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 80, height: 40),
      targetSize: const Size(80, 40),
      home: const WallpaperEffects(blur: 250),
      lock: const WallpaperEffects(blur: 250),
    );

    // The blur is soft anyway, so the GPU can scale this back up.
    final image = await decodePng(bake.effectsHomePng);
    try {
      expect(image.width, 20);
      expect(image.height, 10);
    } finally {
      image.dispose();
    }
  });

  test('a dim or grey effect keeps the full frame size', () async {
    final source = await createPng(80, 40, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 80, 40), ui.Paint()..color = const ui.Color(0xFF3366CC)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 80, height: 40),
      targetSize: const Size(80, 40),
      home: const WallpaperEffects(dim: 128, grey: 200),
      lock: const WallpaperEffects(dim: 128, grey: 200),
    );

    // Only a real blur may be downscaled: dim and grey would visibly soften.
    final image = await decodePng(bake.effectsHomePng);
    try {
      expect(image.width, 80);
      expect(image.height, 40);
    } finally {
      image.dispose();
    }
  });

  test('darkness uses Muzei channel weights on a 64x64 sample', () {
    // Muzei's weights sum to 0.99, so a white sample lands just below 1.
    expect(GroupedWallpaperBaker.darknessOf(Uint8List.fromList(List.filled(64 * 64 * 4, 255))), closeTo(.986, .01));
    expect(GroupedWallpaperBaker.darknessOf(Uint8List.fromList(List.filled(64 * 64 * 4, 0))), 0);
    expect(GroupedWallpaperBaker.darknessOf(Uint8List(0)), .5);
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

  group('framing', () {
    test('a clockwise quarter turn rotates the photo before the fit', () async {
      // Quadrants: top-left red, top-right green, bottom-left blue, bottom-right
      // white. A clockwise turn puts the source bottom-left at the target's
      // top-left, and the source top-left at the target's top-right.
      final source = await createPng(40, 20, (canvas) {
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 20, 10), ui.Paint()..color = const ui.Color(0xFFFF0000));
        canvas.drawRect(const ui.Rect.fromLTWH(20, 0, 20, 10), ui.Paint()..color = const ui.Color(0xFF00FF00));
        canvas.drawRect(const ui.Rect.fromLTWH(0, 10, 20, 10), ui.Paint()..color = const ui.Color(0xFF0000FF));
        canvas.drawRect(const ui.Rect.fromLTWH(20, 10, 20, 10), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      });
      final bake = await bakerFor(source).bake(
        entry: entry(width: 40, height: 20),
        targetSize: const Size(20, 40),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
        homeGeometry: const GroupedFrameGeometry(quarterTurns: 1),
      );

      final image = await decodePng(bake.sharpPng);
      try {
        expect(image.width, 20);
        expect(image.height, 40);
        final rgba = await rawRgba(image);
        final (r0, g0, b0) = pixel(rgba, image.width, 2, 2);
        expect(b0, greaterThan(200), reason: 'source bottom-left (blue) becomes top-left');
        expect(r0, lessThan(60));
        final (r1, g1, b1) = pixel(rgba, image.width, 17, 2);
        expect(r1, greaterThan(200), reason: 'source top-left (red) becomes top-right');
        expect(g1, lessThan(60));
        expect(b1, lessThan(60));
        final (r2, g2, b2) = pixel(rgba, image.width, 2, 37);
        expect(r2, greaterThan(200), reason: 'source bottom-right (white) becomes bottom-left');
        expect(g2, greaterThan(200));
        expect(b2, greaterThan(200));
        final (r3, g3, b3) = pixel(rgba, image.width, 17, 37);
        expect(g3, greaterThan(200), reason: 'source top-right (green) becomes bottom-right');
        expect(r3, lessThan(60));
        expect(b3, lessThan(60));
      } finally {
        image.dispose();
      }
    });

    test('fit letterboxes with opaque black bars', () async {
      final source = await createPng(40, 20, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 40, 20), ui.Paint()..color = const ui.Color(0xFF3366CC)));
      final bake = await bakerFor(source).bake(
        entry: entry(width: 40, height: 20),
        targetSize: const Size(20, 40),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
        homeGeometry: const GroupedFrameGeometry(fit: WallpaperImageFit.fit),
      );

      final image = await decodePng(bake.sharpPng);
      try {
        final rgba = await rawRgba(image);
        final (rBar, gBar, bBar) = pixel(rgba, image.width, 10, 1);
        expect([rBar, gBar, bBar], everyElement(lessThan(10)), reason: 'bar must be opaque black');
        final (r, g, b) = pixel(rgba, image.width, 10, 20);
        expect(b, greaterThan(150), reason: 'the photo itself is centered');
        expect(r, lessThan(90));
      } finally {
        image.dispose();
      }
    });

    test('stretch fills both axes', () async {
      final source = await createPng(40, 20, (canvas) {
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 20, 20), ui.Paint()..color = const ui.Color(0xFFFF0000));
        canvas.drawRect(const ui.Rect.fromLTWH(20, 0, 20, 20), ui.Paint()..color = const ui.Color(0xFF0000FF));
      });
      final bake = await bakerFor(source).bake(
        entry: entry(width: 40, height: 20),
        targetSize: const Size(20, 40),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
        homeGeometry: const GroupedFrameGeometry(fit: WallpaperImageFit.stretch),
      );

      final image = await decodePng(bake.sharpPng);
      try {
        final rgba = await rawRgba(image);
        final (rLeft, gLeft, bLeft) = pixel(rgba, image.width, 5, 20);
        expect(rLeft, greaterThan(200));
        expect(bLeft, lessThan(60));
        final (rRight, gRight, bRight) = pixel(rgba, image.width, 15, 20);
        expect(bRight, greaterThan(200));
        expect(rRight, lessThan(60));
      } finally {
        image.dispose();
      }
    });

    test('a lock-specific geometry writes its own lock base', () async {
      final source = await createPng(40, 20, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 40, 20), ui.Paint()..color = const ui.Color(0xFF3366CC)));
      final bake = await bakerFor(source).bake(
        entry: entry(width: 40, height: 20),
        targetSize: const Size(20, 40),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
        homeGeometry: const GroupedFrameGeometry(),
        lockGeometry: const GroupedFrameGeometry(fit: WallpaperImageFit.fit),
        lockSharesHomeBase: false,
      );

      expect(bake.effectsLockPng, isNot(equals(bake.sharpPng)));
      final lock = await decodePng(bake.effectsLockPng);
      try {
        expect(lock.width, 20);
        expect(lock.height, 40);
      } finally {
        lock.dispose();
      }
    });
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
