/// Size limits of the grouped wallpaper's usage history.
///
/// They live in the model layer because three consumers need them: the store
/// (default and prune bound), the engine's plan and `state.json` (what the
/// notification reads), and the limit dialog. `0` is a valid limit: it turns
/// recording off without deleting what was already recorded.
abstract final class GroupedWallpaperHistoryLimit {
  /// How many photos are remembered when the user never chose a number.
  static const int defaultLimit = 200;

  /// The largest number the user may set.
  static const int maxLimit = 1000;

  /// Clamps a user-supplied value into the supported range.
  static int sanitize(int value) => value.clamp(0, maxLimit);
}
