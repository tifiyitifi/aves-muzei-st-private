import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Muzei's auto-advance intervals.
///
/// Persisted by [seconds] in `SharedPreferences`, so the enum can grow without
/// invalidating existing settings.
enum WallpaperInterval {
  m15(15 * 60),
  m30(30 * 60),
  h1(60 * 60),
  h3(3 * 60 * 60),
  h6(6 * 60 * 60),
  h24(24 * 60 * 60),
  h72(72 * 60 * 60),
  never(0);

  final int seconds;

  new(this.seconds);

  bool get enabled => seconds > 0;

  Duration get duration => Duration(seconds: seconds);

  static WallpaperInterval? tryFromSeconds(int? seconds) {
    if (seconds == null) return null;
    for (final interval in values) {
      if (interval.seconds == seconds) return interval;
    }
    return null;
  }
}

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
  static const WallpaperInterval defaultInterval = WallpaperInterval.never;
  static const WallpaperOrdering defaultOrdering = WallpaperOrdering.newThenRandom;

  final WallpaperInterval interval;
  final WallpaperOrdering ordering;

  const new({
    this.interval = defaultInterval,
    this.ordering = defaultOrdering,
  });

  bool get enabled => interval.enabled;

  WallpaperAutoAdvance copyWith({
    WallpaperInterval? interval,
    WallpaperOrdering? ordering,
  }) => WallpaperAutoAdvance(
    interval: interval ?? this.interval,
    ordering: ordering ?? this.ordering,
  );

  Map<String, Object?> toJsonMap() => {
    'intervalSeconds': interval.seconds,
    'ordering': ordering.name,
  };

  static WallpaperAutoAdvance fromJsonMap(Map<String, Object?> json) {
    final rawSeconds = json['intervalSeconds'];
    final seconds = rawSeconds is int ? rawSeconds : (rawSeconds is num ? rawSeconds.toInt() : null);
    return WallpaperAutoAdvance(
      interval: WallpaperInterval.tryFromSeconds(seconds) ?? defaultInterval,
      ordering: WallpaperOrdering.tryParse(_string(json['ordering'])) ?? defaultOrdering,
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  @override
  List<Object?> get props => [interval, ordering];
}
