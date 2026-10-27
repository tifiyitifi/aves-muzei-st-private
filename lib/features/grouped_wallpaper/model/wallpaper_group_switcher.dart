/// How the wallpaper page lists the groups.
///
/// The choice is this page's own view preference (stored next to its layout), so
/// the visible-range page keeps its look whatever the wallpaper page shows.
enum WallpaperGroupSwitcherStyle {
  /// One horizontal chip row: compact, but a long name truncates.
  chips,

  /// The groups as the page's first grid section, so they follow the grid, list
  /// and mosaic layouts and the pinch-zoom column count like any other section.
  sections,

  /// A fixed five-column grid, the same density as a normal grid zoomed out to
  /// five columns and locked there.
  grid5;

  static WallpaperGroupSwitcherStyle parse(String? value) {
    for (final style in values) {
      if (style.name == value) return style;
    }
    return chips;
  }
}
