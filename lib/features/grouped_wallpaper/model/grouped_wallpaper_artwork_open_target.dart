/// Where tapping the artwork title on the grouped wallpaper view opens it.
///
/// The value is global to the view page, not a group property: switching groups
/// or home/lock surfaces must not change how the user explores a photo.
enum GroupedWallpaperArtworkOpenTarget {
  viewer,
  album,
  group;

  /// Reads a stored enum name, preserving the historical viewer behaviour for a
  /// missing value or one written by a newer build.
  static GroupedWallpaperArtworkOpenTarget tryParse(Object? value) {
    for (final target in values) {
      if (target.name == value) return target;
    }
    return viewer;
  }
}
