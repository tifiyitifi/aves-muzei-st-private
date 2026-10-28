import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// What a wallpaper gesture does.
///
/// The values travel in `state.json` as names, so the native renderer can act on
/// a tap without asking Dart. Adding an action means adding it here and to the
/// renderer's `when`.
enum GroupedWallpaperTapAction {
  /// The gesture does nothing.
  none,

  /// Promote the prefetched slot: the next photo of the group.
  nextArtwork,

  /// Open the grouped wallpaper's view page.
  viewArtwork;

  static GroupedWallpaperTapAction? tryParse(String? value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// The two gestures the wallpaper recognises, shared by both wallpapers.
///
/// Gestures are global (they are muscle memory, not group content), so this
/// config is stored once and copied into every state the engine writes.
@immutable
class GroupedWallpaperGestures extends Equatable {
  static const GroupedWallpaperTapAction defaultDoubleTap = GroupedWallpaperTapAction.nextArtwork;
  static const GroupedWallpaperTapAction defaultThreeFinger = GroupedWallpaperTapAction.viewArtwork;

  final GroupedWallpaperTapAction doubleTap;
  final GroupedWallpaperTapAction threeFinger;

  const new({
    this.doubleTap = defaultDoubleTap,
    this.threeFinger = defaultThreeFinger,
  });

  GroupedWallpaperGestures copyWith({
    GroupedWallpaperTapAction? doubleTap,
    GroupedWallpaperTapAction? threeFinger,
  }) => GroupedWallpaperGestures(
        doubleTap: doubleTap ?? this.doubleTap,
        threeFinger: threeFinger ?? this.threeFinger,
      );

  Map<String, Object?> toJsonMap() => {
        'doubleTap': doubleTap.name,
        'threeFinger': threeFinger.name,
      };

  static GroupedWallpaperGestures fromJsonMap(Map<String, Object?> json) => GroupedWallpaperGestures(
        doubleTap: GroupedWallpaperTapAction.tryParse(json['doubleTap'] is String ? json['doubleTap'] as String : null) ?? defaultDoubleTap,
        threeFinger: GroupedWallpaperTapAction.tryParse(json['threeFinger'] is String ? json['threeFinger'] as String : null) ?? defaultThreeFinger,
      );

  /// Tolerant parse of the stored JSON string: an unknown value falls back to
  /// the default instead of failing the whole read.
  static GroupedWallpaperGestures fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const GroupedWallpaperGestures();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const GroupedWallpaperGestures();
      return fromJsonMap(decoded.map((key, value) => MapEntry(key.toString(), value)));
    } catch (_) {
      return const GroupedWallpaperGestures();
    }
  }

  @override
  List<Object?> get props => [doubleTap, threeFinger];
}
