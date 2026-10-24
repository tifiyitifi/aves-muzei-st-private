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
  /// Double tap advances, unlike Muzei's "temporarily disable effects".
  ///
  /// Not an oversight: the page shows the sharp artwork (effects belong to the
  /// wallpaper), so temporarily disabling them is invisible there, while moving
  /// to the next artwork is the action a wallpaper viewer reaches for. The Muzei
  /// binding is still selectable in the gestures screen.
  static const WallpaperTapAction defaultDoubleTap = WallpaperTapAction.nextArtwork;
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
