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

/// How closing the wallpaper page returns to the visible range.
///
/// In the shared mode one bottom-bar entry renders both pages, so closing only
/// flips that entry back in place. With a temporary entry the page is its own
/// route, so closing navigates to the range page and lets the page's `dispose`
/// take the entry away.
enum WallpaperPageCloseTarget {
  rangeInPlace,
  rangePage,
}

WallpaperPageCloseTarget wallpaperPageCloseTarget(GroupedWallpaperNavMode mode) => mode == GroupedWallpaperNavMode.shared ? WallpaperPageCloseTarget.rangeInPlace : WallpaperPageCloseTarget.rangePage;
