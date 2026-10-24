/// What the wallpaper page shows on its title line.
///
/// Muzei labels the artwork with its source ("从相册中选择"), which reads as a
/// mystery to users who only ever look at the picture. The fork defaults to the
/// file name and keeps the source wording as an option, so the common case needs
/// no interpretation.
///
/// Persisted by [Enum.name], so renaming a value is a data migration; append
/// instead.
enum WallpaperTitleMode {
  /// The current artwork's title, as the collection lists it.
  fileName,

  /// The wallpaper source, e.g. "All photos" or the selected filters.
  sourceName;

  static const WallpaperTitleMode defaultMode = WallpaperTitleMode.fileName;

  static WallpaperTitleMode? tryParse(String? value) {
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}
