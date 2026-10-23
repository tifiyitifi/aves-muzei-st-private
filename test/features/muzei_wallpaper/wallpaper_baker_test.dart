import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_bake.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_baker.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_state_store.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// `WallpaperBaker`: target sizing, cover crop, Muzei's downsample-blur-dim
/// effect pipeline, identity reuse and failure reporting.
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

  WallpaperBaker bakerFor(Uint8List png) => WallpaperBaker(imageProvider: (_) => MemoryImage(png));

  test('bakes sharp and both effects at the target size', () async {
    final source = await createPng(300, 100, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 300, 100), ui.Paint()..color = const ui.Color(0xFF3366CC)));
    final baker = bakerFor(source);

    final bake = await baker.bake(
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

    // The state store is the writer; the baker only returns bytes.
    final directory = await Directory.systemTemp.createTemp('aves_muzei_baker_');
    try {
      final store = WallpaperStateStore(directory);
      await store.writeSlotBytes(3, WallpaperSlotFiles.sharpName, bake.sharpPng);
      await store.writeSlotBytes(3, WallpaperSlotFiles.effectsHomeName, bake.effectsHomePng);
      await store.writeSlotBytes(3, WallpaperSlotFiles.effectsLockName, bake.effectsLockPng);
      for (final name in [WallpaperSlotFiles.sharpName, WallpaperSlotFiles.effectsHomeName, WallpaperSlotFiles.effectsLockName]) {
        final file = store.slotFile(3, name);
        expect(await file.exists(), isTrue, reason: name);
        final image = await decodePng(await file.readAsBytes());
        try {
          expect(image.width, 100, reason: name);
          expect(image.height, 100, reason: name);
        } finally {
          image.dispose();
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
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

  test('cover-crops a portrait source around its center', () async {
    // Horizontal thirds: red, green, blue.
    final source = await createPng(100, 300, (canvas) {
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFFFF0000));
      canvas.drawRect(const ui.Rect.fromLTWH(0, 100, 100, 100), ui.Paint()..color = const ui.Color(0xFF00FF00));
      canvas.drawRect(const ui.Rect.fromLTWH(0, 200, 100, 100), ui.Paint()..color = const ui.Color(0xFF0000FF));
    });
    final bake = await bakerFor(source).bake(
      entry: entry(width: 100, height: 300),
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
    expect(WallpaperBaker.clampTargetSize(const Size(5000, 2500)), const Size(4096, 2048));
    expect(WallpaperBaker.clampTargetSize(const Size(2500, 5000)), const Size(2048, 4096));
    expect(WallpaperBaker.clampTargetSize(const Size(100, 100)), const Size(100, 100));
    expect(() => WallpaperBaker.clampTargetSize(Size.zero), throwsA(isA<WallpaperBakeException>()));
  });

  test('greyscale effect desaturates the sharp image', () async {
    final source = await createPng(64, 64, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint()..color = const ui.Color(0xFFFF0000)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 64, height: 64),
      targetSize: const Size(64, 64),
      home: const WallpaperEffects(blur: 0, dim: 0, grey: 500),
      lock: const WallpaperEffects(blur: 0, dim: 0, grey: 500),
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
      home: const WallpaperEffects(blur: 0, dim: 255, grey: 0),
      lock: const WallpaperEffects(blur: 0, dim: 255, grey: 0),
    );

    expect(bake.darkness, greaterThan(0.9));
    final image = await decodePng(bake.effectsHomePng);
    try {
      final rgba = await rawRgba(image);
      final (r, _, _) = pixel(rgba, image.width, 32, 32);
      expect(r, lessThan(10));
    } finally {
      image.dispose();
    }
  });

  test('blur effect softens the sharp edge', () async {
    // A hard black/white step is the clearest blur probe: without blur the
    // boundary is sharp within a pixel or two; with it, the step widens.
    final source = await createPng(400, 400, (canvas) {
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 200, 400), ui.Paint()..color = const ui.Color(0xFF000000));
      canvas.drawRect(const ui.Rect.fromLTWH(200, 0, 200, 400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    });
    final bake = await bakerFor(source).bake(
      entry: entry(width: 400, height: 400),
      targetSize: const Size(400, 400),
      home: const WallpaperEffects(blur: 500, dim: 0, grey: 0),
      lock: const WallpaperEffects(blur: 500, dim: 0, grey: 0),
    );

    final image = await decodePng(bake.effectsHomePng);
    try {
      final rgba = await rawRgba(image);
      final (left, _, _) = pixel(rgba, image.width, 180, 200);
      final (near, _, _) = pixel(rgba, image.width, 210, 200);
      final (right, _, _) = pixel(rgba, image.width, 390, 200);
      expect(left, lessThan(110), reason: 'left of the boundary should stay dark');
      expect(near, inInclusiveRange(140, 245), reason: 'the step should be softened');
      expect(right, greaterThan(235), reason: 'far right should stay bright');
    } finally {
      image.dispose();
    }
  });

  test('identity effects reuse the sharp bytes', () async {
    final source = await createPng(40, 40, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 40, 40), ui.Paint()..color = const ui.Color(0xFF808080)));
    final bake = await bakerFor(source).bake(
      entry: entry(width: 40, height: 40),
      targetSize: const Size(40, 40),
      home: const WallpaperEffects(blur: 0, dim: 0, grey: 0),
      lock: const WallpaperEffects(blur: 0, dim: 0, grey: 0),
    );

    expect(identical(bake.effectsHomePng, bake.sharpPng), isTrue);
    expect(identical(bake.effectsLockPng, bake.sharpPng), isTrue);
  });

  test('rebaking effects reuses the sharp PNG without decoding the artwork', () async {
    final source = await createPng(80, 80, (canvas) => canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 80, 80), ui.Paint()..color = const ui.Color(0xFF00FF00)));
    final baker = bakerFor(source);
    final baked = await baker.bake(
      entry: entry(width: 80, height: 80),
      targetSize: const Size(80, 80),
      home: const WallpaperEffects(blur: 0, dim: 0, grey: 0),
      lock: const WallpaperEffects(blur: 0, dim: 0, grey: 0),
    );

    final rebaked = await baker.bakeEffects(
      sharpPng: baked.sharpPng,
      home: const WallpaperEffects(blur: 0, dim: 0, grey: 500),
      lock: const WallpaperEffects(blur: 0, dim: 0, grey: 500),
    );
    expect(identical(rebaked.sharpPng, baked.sharpPng), isTrue);
    expect(rebaked.size, baked.size);
    expect(rebaked.darkness, closeTo(baked.darkness, 0.01));
    expect(rebaked.effectsHomePng, isNot(equals(baked.sharpPng)));
    expect(rebaked.effectsLockPng, rebaked.effectsHomePng);
  });

  test('decode failures surface as WallpaperBakeException', () async {
    final baker = WallpaperBaker(imageProvider: (_) => MemoryImage(Uint8List.fromList([0, 1, 2, 3])));
    await expectLater(
      baker.bake(
        entry: entry(),
        targetSize: const Size(100, 100),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
      ),
      throwsA(isA<WallpaperBakeException>()),
    );

    await expectLater(
      baker.bakeEffects(
        sharpPng: Uint8List.fromList([0, 1, 2, 3]),
        home: const WallpaperEffects(),
        lock: const WallpaperEffects(),
      ),
      throwsA(isA<WallpaperBakeException>()),
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
