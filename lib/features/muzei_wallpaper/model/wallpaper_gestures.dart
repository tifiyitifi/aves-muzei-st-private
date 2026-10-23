import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Action assigned to a wallpaper gesture.
///
/// Keeps Muzei's action set. Persisted by [Enum.name], so renaming a value is a
/// data migration; append instead.
enum WallpaperTapAction {
  /// Temporarily reveal the sharp artwork for a few seconds.
  temporaryDisable,

  /// Advance to the next artwork.
  nextArtwork,

  /// Open Aves on the wallpaper page / artwork.
  viewArtwork,

  /// Do nothing.
  none;

  static WallpaperTapAction? tryParse(String? value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// Gesture bindings, matching Muzei's double-tap and three-finger actions.
@immutable
class WallpaperGestures with Equatable {
  static const WallpaperTapAction defaultDoubleTap = WallpaperTapAction.temporaryDisable;
  static const WallpaperTapAction defaultThreeFinger = WallpaperTapAction.none;

  final WallpaperTapAction doubleTap;
  final WallpaperTapAction threeFinger;

  const new({
    this.doubleTap = defaultDoubleTap,
    this.threeFinger = defaultThreeFinger,
  });

  WallpaperGestures copyWith({
    WallpaperTapAction? doubleTap,
    WallpaperTapAction? threeFinger,
  }) => WallpaperGestures(
    doubleTap: doubleTap ?? this.doubleTap,
    threeFinger: threeFinger ?? this.threeFinger,
  );

  Map<String, Object?> toJsonMap() => {
    'doubleTap': doubleTap.name,
    'threeFinger': threeFinger.name,
  };

  static WallpaperGestures fromJsonMap(Map<String, Object?> json) {
    return WallpaperGestures(
      doubleTap: WallpaperTapAction.tryParse(_string(json['doubleTap'])) ?? defaultDoubleTap,
      threeFinger: WallpaperTapAction.tryParse(_string(json['threeFinger'])) ?? defaultThreeFinger,
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  @override
  List<Object?> get props => [doubleTap, threeFinger];
}
