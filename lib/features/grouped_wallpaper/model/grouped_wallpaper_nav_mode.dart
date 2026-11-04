/// How the grouped wallpaper's bottom-bar entry relates to the visible range's.
///
/// The visible-range entry is derived by `withVisibleRangeDestination` and is
/// always present, so the wallpaper entry is placed relative to it instead of
/// being written into the user's own navigation list.
enum GroupedWallpaperNavMode {
  /// One entry that flips between the two pages, the original setup.
  shared,

  /// Its own entry, immediately left of the visible-range entry.
  separateLeft,

  /// Its own entry, immediately right of the visible-range entry.
  separateRight,
}

/// Mode used until the user picks another one.
///
/// Two entries by default: the wallpaper is a peer of the visible range, not a
/// hidden sub-page of it, and the right side is where the range entry's own
/// sub-page used to sit.
const defaultGroupedWallpaperNavMode = GroupedWallpaperNavMode.separateRight;

/// Parses a stored mode, falling back to the default for an unknown value.
GroupedWallpaperNavMode groupedWallpaperNavModeFrom(String? value) => GroupedWallpaperNavMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => defaultGroupedWallpaperNavMode,
    );

/// How closing the wallpaper page returns to the page the user came from.
///
/// The presentation decides it, not the navigation mode alone: a page the bar
/// pushed over another one goes back to it, while the pages that replace the
/// range page in place stay on the range page.
enum WallpaperPageCloseTarget {
  /// One entry hosts both pages, so closing only flips that entry back in place.
  rangeInPlace,

  /// The page was pushed over another one (the bar's own entry), so closing pops
  /// back to it like any other destination.
  pop,

  /// The page replaced the stack (the visible range's "Open wallpaper groups"),
  /// so there is nothing to pop and the range page is its counterpart.
  rangePage,
}

WallpaperPageCloseTarget wallpaperPageCloseTarget(GroupedWallpaperNavMode mode, {required bool canPop}) {
  if (mode == GroupedWallpaperNavMode.shared) return WallpaperPageCloseTarget.rangeInPlace;
  return canPop ? WallpaperPageCloseTarget.pop : WallpaperPageCloseTarget.rangePage;
}
