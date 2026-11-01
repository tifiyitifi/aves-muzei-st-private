import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

export 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';

/// How the next artwork is chosen within the source.
///
/// Mirrors Muzei's three orderings. Persisted by [Enum.name], so renaming a value
/// is a data migration; append instead.
enum WallpaperOrdering {
  /// Walk the source in collection order and wrap around at the end.
  inOrder,

  /// Show artworks added after the last one shown, in order, then fall back to
  /// random. Muzei's default, and ours.
  newThenRandom,

  /// Pick a random artwork, avoiding the current one and recently shown ones.
  random;

  static WallpaperOrdering? tryParse(String? value) {
    for (final ordering in values) {
      if (ordering.name == value) return ordering;
    }
    return null;
  }
}

/// Auto-advance settings. The actual scheduling is owned by the native
/// WorkManager bridge; this is the persisted contract only.
@immutable
class WallpaperAutoAdvance with Equatable {
  static const WallpaperAdvanceInterval defaultInterval = WallpaperAdvanceInterval.off;
  static const WallpaperOrdering defaultOrdering = WallpaperOrdering.newThenRandom;

  /// This wallpaper's own choice from the shared option list. Every group keeps
  /// another one; only the list itself is shared.
  final WallpaperAdvanceInterval interval;
  final WallpaperOrdering ordering;

  const new({
    this.interval = defaultInterval,
    this.ordering = defaultOrdering,
  });

  bool get enabled => interval.enabled;

  WallpaperAutoAdvance copyWith({
    WallpaperAdvanceInterval? interval,
    WallpaperOrdering? ordering,
  }) => WallpaperAutoAdvance(
    interval: interval ?? this.interval,
    ordering: ordering ?? this.ordering,
  );

  Map<String, Object?> toJsonMap() => {
    'intervalSeconds': interval.seconds,
    'ordering': ordering.name,
  };

  static WallpaperAutoAdvance fromJsonMap(Map<String, Object?> json) => WallpaperAutoAdvance(
    // Custom seconds are preserved: the option list is user-editable, so an
    // unknown value is not a corrupt setting.
    interval: WallpaperAdvanceInterval.fromSeconds(json['intervalSeconds']),
    ordering: WallpaperOrdering.tryParse(_string(json['ordering'])) ?? defaultOrdering,
  );

  static String? _string(Object? value) => value is String ? value : null;

  @override
  List<Object?> get props => [interval, ordering];
}
