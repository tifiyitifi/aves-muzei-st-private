import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:flutter/painting.dart';

/// A baked wallpaper frame: one opaque PNG per surface plus the sharp original.
///
/// The effect PNGs are byte-identical to [sharpPng] when their configuration is
/// the identity, so the state store can skip writing a second copy.
class GroupedWallpaperBake {
  final Uint8List sharpPng;
  final Uint8List effectsHomePng;
  final Uint8List effectsLockPng;
  final Size size;

  /// Average luminance of the sharp frame, in `0..1`.
  final double darkness;

  const new({
    required this.sharpPng,
    required this.effectsHomePng,
    required this.effectsLockPng,
    required this.size,
    required this.darkness,
  });
}

class GroupedWallpaperBakeException implements Exception {
  final String message;
  final Object? cause;

  const new(this.message, {this.cause});

  @override
  String toString() => 'GroupedWallpaperBakeException: $message';
}

/// Renders one photo to the wallpaper's cover crop, plus the home/lock effects.
///
/// The effect math follows Muzei's `MuzeiBlurRenderer`: blur at a quarter of the
/// surface height, then upscale; grey via a desaturation matrix; dim via the
/// artwork's own darkness. Dart owns it because Aves already has the EXIF-aware
/// decoders and the SVG rasterizer; the native renderer only uploads the
/// resulting textures.
class GroupedWallpaperBaker {
  /// Conservative `GL_MAX_TEXTURE_SIZE` floor; scrollable wallpapers can be
  /// wider than the screen, so the target itself has to be bounded.
  static const int maxDimension = 4096;

  /// Muzei blurs at a quarter of the surface height, then lets the GPU scale the
  /// result back up. Keeping the bake at that size saves most of the blur cost
  /// while looking the same after the final upscale.
  static const int effectsDownscale = 4;

  static const int darknessSampleSide = 64;

  /// Decode budget for cover-cropping, so an extreme aspect ratio cannot require
  /// a very large intermediate bitmap.
  static const double maxDecodePixels = 16 * 1000 * 1000;

  static const Duration decodeTimeout = Duration(seconds: 60);

  /// Injected in tests so baking can run on the host without platform media
  /// channels; production uses the entry's EXIF-aware full-image provider.
  final ImageProvider Function(AvesEntry entry) _imageProvider;

  new({ImageProvider Function(AvesEntry entry)? imageProvider}) : _imageProvider = imageProvider ?? _defaultImageProvider;

  /// Clamps the requested wallpaper surface to the texture limit while keeping
  /// its aspect ratio.
  static Size clampTargetSize(Size requested) {
    if (!requested.width.isFinite || !requested.height.isFinite || requested.width <= 0 || requested.height <= 0) {
      throw GroupedWallpaperBakeException('invalid target size: $requested');
    }
    final longest = math.max(requested.width, requested.height);
    final scale = longest > maxDimension ? maxDimension / longest : 1.0;
    return Size(
      math.max(1, (requested.width * scale).round()).toDouble(),
      math.max(1, (requested.height * scale).round()).toDouble(),
    );
  }

  /// Bakes the sharp crop and both effect images from [entry].
  ///
  /// [lock] must already be the effective lock effects: when the user links the
  /// surfaces, the caller passes the home values for both, exactly as Muzei
  /// shares one blurred layer.
  Future<GroupedWallpaperBake> bake({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
  }) async {
    final target = clampTargetSize(targetSize);
    ui.Image? decoded, sharp;
    try {
      decoded = await _decode(entry, target);
      sharp = await _coverCrop(decoded, target);
      final sharpPng = await _encodePng(sharp);
      final darkness = await _measureDarkness(sharp);
      final homePng = home.isIdentity ? sharpPng : await _renderEffects(sharp: sharp, effects: home, darkness: darkness);
      final lockPng = lock == home
          ? homePng
          : lock.isIdentity
              ? sharpPng
              : await _renderEffects(sharp: sharp, effects: lock, darkness: darkness);
      return GroupedWallpaperBake(
        sharpPng: sharpPng,
        effectsHomePng: homePng,
        effectsLockPng: lockPng,
        size: target,
        darkness: darkness,
      );
    } on GroupedWallpaperBakeException {
      rethrow;
    } catch (error, stack) {
      groupedWallpaperLog.e('bake failed entry=${entry.id} target=$target', error, stack);
      throw GroupedWallpaperBakeException('failed to bake entry ${entry.id}', cause: error);
    } finally {
      sharp?.dispose();
      decoded?.dispose();
    }
  }

  static ImageProvider _defaultImageProvider(AvesEntry entry) => entry.isSvg
      // Flutter's codecs cannot decode SVG; the platform rasterizes the full
      // image region instead, which is also what the viewer's tiled path does.
      ? entry.getRegion(sampleSize: 1, region: entry.fullImageRegion)
      : entry.getFullImage();

  /// Decodes the artwork at cover resolution.
  ///
  /// `getFullImage` already applies EXIF orientation (and user rotation), so the
  /// decoded bitmap is in display orientation and only needs a cover crop.
  Future<ui.Image> _decode(AvesEntry entry, Size target) async {
    final provider = _resizeForCover(_imageProvider(entry), entry, target);
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (completer.isCompleted) return;
        // Keep our own handle so the image survives the listener's disposal.
        final image = info.image.clone();
        info.dispose();
        completer.complete(image);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack ?? StackTrace.current);
      },
    );
    stream.addListener(listener);
    try {
      final image = await completer.future.timeout(decodeTimeout);
      // The baked PNG replaces the decoded bitmap; do not leave a large
      // intermediate in the image cache.
      unawaited(provider.evict());
      return image;
    } on TimeoutException catch (error) {
      throw GroupedWallpaperBakeException('timed out decoding entry ${entry.id}', cause: error);
    } finally {
      stream.removeListener(listener);
    }
  }

  ImageProvider _resizeForCover(ImageProvider provider, AvesEntry entry, Size target) {
    if (entry.isSvg) return provider;
    final (width, height) = _decodeSize(entry.displaySize, target);
    return ResizeImage(
      provider,
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  /// Width/height to hand to the decoder: decode only as much as the cover crop
  /// can use, and never more than the decode budget.
  (int, int) _decodeSize(Size source, Size target) {
    if (source.isEmpty) return (target.width.round(), target.height.round());
    var scale = math.min(math.max(target.width / source.width, target.height / source.height), 1.0);
    final pixels = source.width * source.height * scale * scale;
    if (pixels > maxDecodePixels) {
      scale *= math.sqrt(maxDecodePixels / pixels);
    }
    return (
      math.max(1, (source.width * scale).round()),
      math.max(1, (source.height * scale).round()),
    );
  }

  /// Center-crops [image] to [target] using a cover fit.
  Future<ui.Image> _coverCrop(ui.Image image, Size target) async {
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    final targetAspect = target.width / target.height;
    final sourceAspect = sourceWidth / sourceHeight;
    final ui.Rect source;
    if (sourceAspect > targetAspect) {
      final width = sourceHeight * targetAspect;
      source = ui.Rect.fromLTWH((sourceWidth - width) / 2, 0, width, sourceHeight);
    } else {
      final height = sourceWidth / targetAspect;
      source = ui.Rect.fromLTWH(0, (sourceHeight - height) / 2, sourceWidth, height);
    }
    final destination = ui.Rect.fromLTWH(0, 0, target.width, target.height);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Wallpapers are opaque; an image with alpha must not show the previous
    // wallpaper or undefined GL memory through it.
    canvas.drawRect(destination, ui.Paint()..color = const ui.Color(0xFF000000));
    canvas.drawImageRect(
      image,
      source,
      destination,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(target.width.round(), target.height.round());
    } finally {
      picture.dispose();
    }
  }

  Future<Uint8List> _renderEffects({
    required ui.Image sharp,
    required WallpaperEffects effects,
    required double darkness,
  }) async {
    final targetWidth = sharp.width;
    final targetHeight = sharp.height;
    final blurWidth = math.max(2, (targetWidth / effectsDownscale).round());
    final blurHeight = math.max(2, (targetHeight / effectsDownscale).round());
    final bounds = ui.Rect.fromLTWH(0, 0, blurWidth.toDouble(), blurHeight.toDouble());
    final source = ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble());
    final sigma = effects.sigmaFor(targetHeight.toDouble(), downscale: targetHeight / blurHeight);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xFF000000));

    final layerPaint = ui.Paint();
    if (sigma > 0) {
      layerPaint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp);
    }
    if (effects.grey > 0) {
      layerPaint.colorFilter = ui.ColorFilter.matrix(effects.desaturationMatrix);
    }
    if (sigma > 0) {
      canvas.saveLayer(bounds, layerPaint);
      canvas.drawImageRect(sharp, source, bounds, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      canvas.restore();
    } else {
      canvas.drawImageRect(
        sharp,
        source,
        bounds,
        layerPaint..filterQuality = ui.FilterQuality.medium,
      );
    }

    final dimAlpha = effects.dimAlpha(darkness);
    if (dimAlpha > 0) {
      canvas.drawRect(bounds, ui.Paint()..color = ui.Color.fromARGB(dimAlpha, 0, 0, 0));
    }

    final picture = recorder.endRecording();
    ui.Image blurred;
    try {
      blurred = await picture.toImage(blurWidth, blurHeight);
    } finally {
      picture.dispose();
    }
    try {
      final upRecorder = ui.PictureRecorder();
      final upCanvas = ui.Canvas(upRecorder);
      upCanvas.drawImageRect(
        blurred,
        ui.Rect.fromLTWH(0, 0, blurWidth.toDouble(), blurHeight.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final upPicture = upRecorder.endRecording();
      try {
        final output = await upPicture.toImage(targetWidth, targetHeight);
        try {
          return await _encodePng(output);
        } finally {
          output.dispose();
        }
      } finally {
        upPicture.dispose();
      }
    } finally {
      blurred.dispose();
    }
  }

  /// Average luminance in `0..1`, using Muzei's channel weights so the dim
  /// curve behaves like the original renderer.
  Future<double> _measureDarkness(ui.Image image) async {
    const side = darknessSampleSide;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final thumbnail = await picture.toImage(side, side);
    picture.dispose();
    try {
      final data = await thumbnail.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const GroupedWallpaperBakeException('darkness sampling returned no data');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      var total = 0.0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        total += 0.21 * bytes[i] + 0.71 * bytes[i + 1] + 0.07 * bytes[i + 2];
      }
      return (total / (side * side) / 256).clamp(0.0, 1.0);
    } finally {
      thumbnail.dispose();
    }
  }

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const GroupedWallpaperBakeException('PNG encoding returned no data');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
