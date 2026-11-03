import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_frame_geometry.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
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

  /// A decode that runs longer than this is treated as failed.
  ///
  /// Baking is serialized, so waiting a minute for one photo blocks every tap
  /// that follows it; picking another photo is better than a stuck queue.
  static const Duration decodeTimeout = Duration(seconds: 15);

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

  /// Bakes the sharp home frame, the optional lock base, and both effect images.
  ///
  /// [lock] must already be the effective lock effects: when the user links the
  /// surfaces, the caller passes the home values for both, exactly as Muzei
  /// shares one blurred layer.
  ///
  /// [homeGeometry] and [lockGeometry] are the *resolved* rotation and fit of
  /// each surface, applied before the effects. When [lockSharesHomeBase] is true
  /// the lock surface reuses the home frame, so a device with one surface
  /// configuration pays for one decode and one extra encode at most.
  Future<GroupedWallpaperBake> bake({
    required AvesEntry entry,
    required Size targetSize,
    required WallpaperEffects home,
    required WallpaperEffects lock,
    GroupedFrameGeometry homeGeometry = const GroupedFrameGeometry(),
    GroupedFrameGeometry lockGeometry = const GroupedFrameGeometry(),
    Size? lockTargetSize,
    bool lockSharesHomeBase = true,
  }) async {
    final target = clampTargetSize(targetSize);
    final lockTarget = lockSharesHomeBase ? target : clampTargetSize(lockTargetSize ?? targetSize);
    final watch = Stopwatch()..start();
    final timings = <String, int>{};
    ui.Image? decoded, sharp, lockSharp;
    try {
      // One decode for both surfaces: the required resolution is the larger of
      // the two, after undoing the quarter turn that will be applied later.
      final source = await _timed(timings, 'decode', () => _decode(entry, _decodeTarget(target, homeGeometry, lockTarget, lockGeometry)));
      decoded = source;
      final cropped = await _timed(timings, 'crop', () => _renderFrame(source, target, homeGeometry));
      sharp = cropped;
      final sharpPng = await _timed(timings, 'encode', () => _encodePng(cropped));
      final darkness = await _timed(timings, 'darkness', () => _measureDarkness(cropped));
      final bool lockUsesOwnBase = !lockSharesHomeBase;
      final lockBase = lockUsesOwnBase ? await _timed(timings, 'crop', () => _renderFrame(source, lockTarget, lockGeometry)) : cropped;
      if (lockBase != cropped) lockSharp = lockBase;
      final lockBasePng = lockUsesOwnBase ? await _timed(timings, 'encode', () => _encodePng(lockBase)) : sharpPng;
      final homePng = home.isIdentity ? sharpPng : await _timed(timings, 'effects', () => _renderEffects(sharp: cropped, effects: home, darkness: darkness));
      final lockPng = lock.isIdentity
          ? lockBasePng
          : lock == home && !lockUsesOwnBase
          ? homePng
          : await _timed(timings, 'effects', () => _renderEffects(sharp: lockBase, effects: lock, darkness: darkness));
      groupedWallpaperLog.d(
        'bake.done entry=${entry.id} target=${target.width.round()}x${target.height.round()} ms=${watch.elapsedMilliseconds}'
        ' decode=${timings['decode']} crop=${timings['crop']} darkness=${timings['darkness']}'
        ' effects=${timings['effects'] ?? 0} encode=${timings['encode'] ?? 0}',
      );
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
      lockSharp?.dispose();
      sharp?.dispose();
      decoded?.dispose();
    }
  }

  /// Runs [action], adding its duration to [timings] under [key].
  ///
  /// The bake is the wallpaper's whole latency, so each stage is measured where
  /// it happens rather than guessed from the total.
  static Future<T> _timed<T>(Map<String, int> timings, String key, Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      timings[key] = (timings[key] ?? 0) + watch.elapsedMilliseconds;
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
  /// decoded bitmap is in display orientation and only needs the frame geometry.
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

  /// The decode bounds one surface needs, before the quarter turn is applied.
  ///
  /// Glide/the decoder crops in the stored orientation, so a quarter turn has to
  /// swap the requested sides: decoding to the display size first and rotating
  /// afterwards would cut the wrong part of the photo and lose resolution.
  static Size _decodeTargetFor(Size target, GroupedFrameGeometry geometry) => geometry.quarterTurns.isOdd ? Size(target.height, target.width) : target;

  /// The decode bounds both surfaces need, as one box.
  static Size _decodeTarget(Size homeTarget, GroupedFrameGeometry home, Size lockTarget, GroupedFrameGeometry lock) {
    final a = _decodeTargetFor(homeTarget, home);
    final b = _decodeTargetFor(lockTarget, lock);
    return Size(math.max(a.width, b.width), math.max(a.height, b.height));
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

  /// Renders [image] into a [target]-sized frame with [geometry].
  ///
  /// The quarter turn is applied by rotating the canvas about the frame centre,
  /// then the photo is fitted into the target box that is swapped for an odd
  /// turn. That keeps the operation order explicit — orient the photo first,
  /// then fit it — and needs no intermediate rotated bitmap.
  Future<ui.Image> _renderFrame(ui.Image image, Size target, GroupedFrameGeometry geometry) async {
    final turns = geometry.quarterTurns % 4;
    final sourceWidth = image.width.toDouble();
    final sourceHeight = image.height.toDouble();
    final rotatedFrame = turns.isOdd ? Size(target.height, target.width) : target;
    final (scaleX, scaleY) = switch (geometry.fit) {
      WallpaperImageFit.fill => _uniformScale(sourceWidth, sourceHeight, rotatedFrame, cover: true),
      WallpaperImageFit.fit => _uniformScale(sourceWidth, sourceHeight, rotatedFrame, cover: false),
      // Stretch scales each axis independently, so the whole photo covers the
      // frame with a distortion instead of bars or a crop.
      WallpaperImageFit.stretch => (rotatedFrame.width / sourceWidth, rotatedFrame.height / sourceHeight),
    };
    final destination = ui.Rect.fromCenter(
      center: Offset.zero,
      width: sourceWidth * scaleX,
      height: sourceHeight * scaleY,
    );
    final source = ui.Rect.fromLTWH(0, 0, sourceWidth, sourceHeight);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // Wallpapers are opaque; an image with alpha must not show the previous
    // wallpaper or undefined GL memory through it.
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, target.width, target.height), ui.Paint()..color = const ui.Color(0xFF000000));
    canvas.save();
    canvas.translate(target.width / 2, target.height / 2);
    if (turns != 0) canvas.rotate(math.pi / 2 * turns);
    canvas.drawImageRect(
      image,
      source,
      destination,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(target.width.round(), target.height.round());
    } finally {
      picture.dispose();
    }
  }

  /// A centered, uniform scale that either covers or fits [frame].
  static (double, double) _uniformScale(double sourceWidth, double sourceHeight, Size frame, {required bool cover}) {
    final widthScale = frame.width / sourceWidth;
    final heightScale = frame.height / sourceHeight;
    final scale = cover ? math.max(widthScale, heightScale) : math.min(widthScale, heightScale);
    return (scale, scale);
  }

  /// Renders the effect image of a frame that was already baked to [photo].
  ///
  /// The native path writes the sharp frame and calls this for the effects, so
  /// the effect math keeps a single implementation: the one the effects page
  /// previews on the GPU.
  Future<Uint8List> renderEffectsFromFile(File photo, Size size, WallpaperEffects effects, double darkness) async {
    final downscale = effects.blur > 0 ? effectsDownscale : 1;
    final width = math.max(2, (size.width / downscale).round());
    final height = math.max(2, (size.height / downscale).round());
    final image = await _decodeFile(photo, width, height);
    try {
      return await _renderEffects(sharp: image, effects: effects, darkness: darkness);
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image> _decodeFile(File photo, int width, int height) async {
    final codec = await ui.instantiateImageCodec(await photo.readAsBytes(), targetWidth: width, targetHeight: height);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> _renderEffects({
    required ui.Image sharp,
    required WallpaperEffects effects,
    required double darkness,
  }) async {
    // A real blur is soft by nature, so it is baked at a quarter of the frame
    // and the GPU scales it back up (as Muzei does). Dim and grey alone would
    // visibly soften the sharp photo instead, so they stay full size.
    final downscale = effects.blur > 0 ? effectsDownscale : 1;
    final width = math.max(2, (sharp.width / downscale).round());
    final height = math.max(2, (sharp.height / downscale).round());
    final bounds = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final source = ui.Rect.fromLTWH(0, 0, sharp.width.toDouble(), sharp.height.toDouble());
    final sigma = effects.sigmaFor(sharp.height.toDouble(), downscale: sharp.height / height);

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
    try {
      final output = await picture.toImage(width, height);
      try {
        return await _encodePng(output);
      } finally {
        output.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Average luminance in `0..1`, using Muzei's channel weights so the dim
  /// curve behaves like the original renderer.
  ///
  /// The weights are the one copy for both bakers: the platform only sends the
  /// 64×64 sample, and the dim curve that consumes it lives here too.
  static double darknessOf(Uint8List rgba) {
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return .5;
    var total = 0.0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      total += 0.21 * rgba[i] + 0.71 * rgba[i + 1] + 0.07 * rgba[i + 2];
    }
    return (total / pixels / 256).clamp(0.0, 1.0);
  }

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
      return darknessOf(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
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
