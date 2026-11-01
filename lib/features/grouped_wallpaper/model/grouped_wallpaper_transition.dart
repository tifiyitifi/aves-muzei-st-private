/// The duration of [GroupedWallpaperTransition.standard], for `const` defaults.
///
/// A field of an enum instance is not a constant expression in Dart, so the
/// default of a `const` constructor cannot read it from the enum below.
const int defaultGroupedWallpaperTransitionMs = 300;

/// How the wallpaper animates a photo change.
///
/// It is a global preference, not a group effect: a crossfade runs between two
/// frames that may belong to different groups, and the effects blob is the frame
/// cache key, so changing an animation duration there would invalidate every
/// baked frame for a value none of them draws.
enum GroupedWallpaperTransition {
  off(0),
  short(150),
  standard(300),
  long(500);

  final int durationMs;

  new(this.durationMs);

  /// Muzei hardcodes 750 ms; a tap here should feel immediate, so 300 is the
  /// middle ground the device was tuned with.
  static const GroupedWallpaperTransition defaultTransition = standard;

  static GroupedWallpaperTransition tryParse(Object? value) {
    for (final transition in values) {
      if (transition.name == value) return transition;
    }
    return defaultTransition;
  }

  /// The closest switch for a duration read back from `state.json`.
  ///
  /// Tolerant on purpose: a file written by another build must never freeze the
  /// wallpaper on a duration the enum cannot name.
  static GroupedWallpaperTransition fromDuration(Object? value) {
    final ms = value is num ? value.toInt() : null;
    if (ms == null) return defaultTransition;
    var closest = values.first;
    for (final transition in values) {
      if ((transition.durationMs - ms).abs() < (closest.durationMs - ms).abs()) closest = transition;
    }
    return closest;
  }
}
