import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/images.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:flutter/painting.dart';

/// A baked wallpaper frame: one opaque PNG at the surface's aspect ratio.
class GroupedWallpaperBake {
  final Uint8List png;
  final Size size;

  const new({required this.png, required this.size});
}

class GroupedWallpaperBakeException implements Exception {
  final String message;
  final Object? cause;

  const new(this.message, {this.cause});

  @override
  String toString() => 'GroupedWallpaperBakeException: $message';
}

/// Renders one photo to the wallpaper's cover crop.
///
/// The grouped wallpaper shows a single sharp image (no blur, dim or greyscale),
/// so this is the Muzei bake without the effect pipeline: decode at cover
/// resolution, center-crop, encode PNG. Dart owns it because Aves already has the
/// EXIF-aware decoders and the SVG rasterizer; the native renderer only uploads
/// the resulting texture.
class GroupedWallpaperBaker {
  /// Conservative `GL_MAX_TEXTURE_SIZE` floor; scrollable wallpapers can be
  /// wider than the screen, so the target itself has to be bounded.
  static const int maxDimension = 4096;

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

  Future<GroupedWallpaperBake> bake({required AvesEntry entry, required Size targetSize}) async {
    final target = clampTargetSize(targetSize);
    ui.Image? decoded, sharp;
    try {
      decoded = await _decode(entry, target);
      sharp = await _coverCrop(decoded, target);
      return GroupedWallpaperBake(png: await _encodePng(sharp), size: target);
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

  static Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const GroupedWallpaperBakeException('PNG encoding returned no data');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
