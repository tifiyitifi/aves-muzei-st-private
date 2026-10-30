/// What a password lock protects.
///
/// Each kind owns its own PIN and its own on/off flag: a user may want to keep
/// the gallery range fixed without also guarding which group the wallpaper
/// plays, and the two are unrelated actions on unrelated pages.
enum WallpaperLockKind {
  /// Editing the gallery visible range and temporarily ignoring it while
  /// browsing a wallpaper group.
  visibleRange,

  /// Making another group the wallpaper, from the page or the notification.
  groupSwitch,
}
