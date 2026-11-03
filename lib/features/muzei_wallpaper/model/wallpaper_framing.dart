import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// How a photo is oriented on one wallpaper surface.
///
/// Only the *direction* is the user's: whether a photo is rotated at all is
/// decided per photo from its aspect ratio and the surface it lands on (see the
/// grouped wallpaper's `wallpaperRotationQuarterTurns`). A photo whose
/// orientation already matches the surface is never rotated.
enum WallpaperRotation {
  off,
  clockwise,
  counterClockwise,

  /// A fresh direction for every photo the wallpaper selects.
  ///
  /// The draw happens when the photo is selected, not on every bake: a re-bake
  /// (an effect slider, a layout change, stepping back through the history) must
  /// not flip the picture that is already on screen.
  random;

  /// Persisted by name: the database must not depend on the declaration order.
  static WallpaperRotation tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return off;
  }
}

/// How a photo is mapped onto a surface whose aspect ratio it does not match.
enum WallpaperImageFit {
  /// Cover: fill the surface and crop the overflow. The app's historical
  /// behaviour, and the default so an upgraded group keeps its frame.
  fill,

  /// Contain: show the whole photo, with opaque black bars.
  fit,

  /// Scale each axis independently, distorting the photo.
  stretch;

  /// Persisted by name, with [fill] as the fallback for an unknown value.
  static WallpaperImageFit tryParse(Object? value) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return fill;
  }
}

/// Rotation and fit for one surface, stored next to that surface's effects.
///
/// Rotation is applied before the fit: the photo is first settled into the
/// orientation it should be seen in, then fitted to the screen. The two are
/// orthogonal on purpose, so choosing "stretch" never changes which photos are
/// rotated.
@immutable
class WallpaperFraming with Equatable {
  final WallpaperRotation rotation;
  final WallpaperImageFit fit;

  const new({
    this.rotation = WallpaperRotation.off,
    this.fit = WallpaperImageFit.fill,
  });

  bool get isDefault => rotation == WallpaperRotation.off && fit == WallpaperImageFit.fill;

  WallpaperFraming copyWith({WallpaperRotation? rotation, WallpaperImageFit? fit}) => WallpaperFraming(
    rotation: rotation ?? this.rotation,
    fit: fit ?? this.fit,
  );

  Map<String, Object?> toJsonMap() => {
    'rotation': rotation.name,
    'fit': fit.name,
  };

  static WallpaperFraming fromJsonMap(Map<String, Object?>? json) {
    if (json == null) return const WallpaperFraming();
    return WallpaperFraming(
      rotation: WallpaperRotation.tryParse(json['rotation']),
      fit: WallpaperImageFit.tryParse(json['fit']),
    );
  }

  @override
  List<Object?> get props => [rotation, fit];
}
