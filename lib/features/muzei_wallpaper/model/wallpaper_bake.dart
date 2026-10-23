import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// The three PNGs and metadata produced by one wallpaper bake.
///
/// The baker returns bytes instead of writing files: [WallpaperStateStore] owns
/// the atomic write and slot layout, so it can be tested and reused by the
/// effects-only rebake without baking the source again.
@immutable
class WallpaperBake {
  /// Final size of every PNG, already clamped to the GPU texture limit.
  final Size size;

  /// Average luminance of the cropped artwork in `0..1`, used for dimming.
  final double darkness;

  final Uint8List sharpPng;
  final Uint8List effectsHomePng;
  final Uint8List effectsLockPng;

  const new({
    required this.size,
    required this.darkness,
    required this.sharpPng,
    required this.effectsHomePng,
    required this.effectsLockPng,
  });

  @override
  String toString() => '$runtimeType{size=$size, darkness=${darkness.toStringAsFixed(3)}}';
}

/// A bake failure the controller treats as "skip this artwork and retry".
class WallpaperBakeException implements Exception {
  final String message;
  final Object? cause;

  const new(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' (cause: $cause)' : ''}';
}
