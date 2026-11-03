import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The smallest long/short aspect ratio that makes auto-rotation worthwhile on
/// a surface whose own orientation clearly differs.
///
/// A landscape photo on a portrait phone always shows more of itself when it is
/// rotated, but the gain is `aspect²`, so a nearly square photo gains almost
/// nothing. The rotation margin below is `2·ln(1.2)`, which asks the rotated
/// orientation to be at least 44% closer to the surface aspect; on a typical
/// phone that is exactly a 1.2:1 photo.
const double wallpaperRotationAspectThreshold = 1.2;

/// The minimum improvement, in log-aspect units, that justifies a quarter turn.
final double wallpaperRotationMargin = 2 * math.log(wallpaperRotationAspectThreshold);

/// How one surface's frame is rendered: a quarter turn plus an image fit.
///
/// This is the *resolved* geometry, not the user's setting: the engine turns a
/// [WallpaperFraming] into one of these per photo, and the bakers only apply it.
@immutable
class GroupedFrameGeometry with Equatable {
  /// Clockwise quarter turns: 0, 1 or 3 (3 is a counter-clockwise turn).
  final int quarterTurns;

  final WallpaperImageFit fit;

  const new({
    this.quarterTurns = 0,
    this.fit = WallpaperImageFit.fill,
  });

  int get rotationDegrees => (quarterTurns % 4) * 90;

  bool get isIdentity => quarterTurns % 4 == 0 && fit == WallpaperImageFit.fill;

  Map<String, Object?> toJsonMap() => {
    'quarterTurns': quarterTurns % 4,
    'fit': fit.name,
  };

  static GroupedFrameGeometry fromJsonMap(Map<String, Object?>? json) {
    if (json == null) return const GroupedFrameGeometry();
    final turns = json['quarterTurns'];
    return GroupedFrameGeometry(
      quarterTurns: turns is int ? turns % 4 : 0,
      fit: WallpaperImageFit.tryParse(json['fit']),
    );
  }

  @override
  List<Object?> get props => [quarterTurns % 4, fit];
}

/// Whether [photoSize] is "the wrong way round" for [surfaceSize], by enough to
/// be worth rotating.
///
/// Both sizes are in display orientation (EXIF applied). The surface decides
/// which way the mismatch points; the margin decides whether it is worth it.
/// Under both cover/contain (maximize the shared area) and stretch (minimize
/// distortion), the best orientation is the one whose aspect is closest to the
/// surface's in log space, so the comparison is:
///
///     |ln(1 / (photo · surface))| + margin < |ln(photo / surface)|
///
/// A square surface is neutral and never rotates anything.
bool wallpaperNeedsRotation(Size photoSize, Size surfaceSize) {
  if (photoSize.width <= 0 || photoSize.height <= 0 || surfaceSize.width <= 0 || surfaceSize.height <= 0) return false;
  final photoAspect = photoSize.width / photoSize.height;
  final surfaceAspect = surfaceSize.width / surfaceSize.height;
  // Only a mismatch of orientation can be helped at all.
  if ((photoAspect > 1) == (surfaceAspect > 1)) return false;
  final photoLog = math.log(photoAspect);
  final surfaceLog = math.log(surfaceAspect);
  final cost = (photoLog - surfaceLog).abs();
  final rotatedCost = (photoLog + surfaceLog).abs();
  // The epsilon keeps the declared 1.2 boundary inclusive after rounding.
  return rotatedCost + wallpaperRotationMargin <= cost + 1e-9;
}

/// The quarter turns to apply to [photoSize] on [surfaceSize] for one surface.
///
/// [randomClockwise] is the direction drawn when the photo was selected. It is
/// ignored by every other setting, and kept by the caller so a re-bake of the
/// same photo cannot flip it.
int wallpaperRotationQuarterTurns({
  required Size photoSize,
  required Size surfaceSize,
  required WallpaperRotation rotation,
  required bool randomClockwise,
}) {
  if (!wallpaperNeedsRotation(photoSize, surfaceSize)) return 0;
  return switch (rotation) {
    WallpaperRotation.off => 0,
    WallpaperRotation.clockwise => 1,
    WallpaperRotation.counterClockwise => 3,
    WallpaperRotation.random => randomClockwise ? 1 : 3,
  };
}

/// The stable direction for one slot's [seed].
///
/// [seed] is drawn when the photo is selected, not derived from the entry, so
/// the same photo can come back in another direction later while a re-bake of
/// the current queue never changes it. The lock surface uses a different salt so
/// a home and lock frame of the same photo need not rotate the same way.
bool wallpaperRandomClockwise(int seed, {required bool lock}) {
  var hash = (seed ^ (lock ? 0x9e3779b9 : 0x85ebca6b)) & 0xffffffff;
  hash = (hash ^ (hash >> 15)) * 0x2c1b3c6d & 0xffffffff;
  hash = (hash ^ (hash >> 12)) & 0xffffffff;
  return hash & 1 == 0;
}
