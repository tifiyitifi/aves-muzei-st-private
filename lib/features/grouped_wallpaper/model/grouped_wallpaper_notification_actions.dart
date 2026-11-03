/// Which button set the wallpaper bar offers while the phone is unlocked.
///
/// The bar has two sets: the wallpaper's own photos, or the groups the
/// wallpaper rotates. The lock screen always offers the groups, because leaving
/// the group on screen is what the lock is there to prevent; this switch only
/// decides the unlocked default. The expanded bar's first button still flips
/// the set for the current session, so both remain reachable.
enum GroupedWallpaperNotificationActions {
  /// Previous/next photo, like a wallpaper double tap.
  wallpaper,

  /// Previous/next group, plus the group lock.
  group;

  /// What an unlocked bar shows until the user picks otherwise.
  ///
  /// It is what every build did before the switch existed, so an upgrade keeps
  /// the bar the user knows.
  static const GroupedWallpaperNotificationActions defaultActions = wallpaper;

  static GroupedWallpaperNotificationActions tryParse(Object? value) {
    for (final actions in values) {
      if (actions.name == value) return actions;
    }
    return defaultActions;
  }
}
