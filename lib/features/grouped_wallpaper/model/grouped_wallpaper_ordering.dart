/// How the grouped wallpaper chooses the next photo within its group.
///
/// Mirrors Muzei's three orderings, including its default: photos added since
/// the wallpaper last moved are shown first, in order, and the group falls back
/// to random once none are left. Persisted by [Enum.name], so renaming a value is
/// a data migration; append instead.
enum GroupedWallpaperOrdering {
  /// Walk the group in collection order (newest first) and wrap around at the
  /// end.
  inOrder,

  /// Show photos added after the last one shown, in order, then fall back to
  /// random. Muzei's default, and ours.
  newThenRandom,

  /// Pick a random photo, avoiding the one on screen and the recently shown
  /// ones.
  random;

  static const GroupedWallpaperOrdering defaultOrdering = newThenRandom;

  /// Tolerant parse of a persisted or `state.json` value: an unknown or missing
  /// value falls back to the default instead of failing the whole read.
  static GroupedWallpaperOrdering tryParse(Object? value) {
    for (final ordering in values) {
      if (ordering.name == value) return ordering;
    }
    return defaultOrdering;
  }
}
