/// What a password lock protects.
///
/// Each kind owns its own PIN: a user may want to keep the gallery range fixed
/// without also guarding which group the wallpaper plays, and the two are
/// unrelated actions on unrelated pages. The lock states are independent too:
/// the visible range's own `locked` column, and the group switch flag in AppMeta.
enum WallpaperLockKind {
  /// Editing the gallery visible range, unlocking it, and temporarily ignoring
  /// it while browsing a wallpaper group.
  visibleRange,

  /// Leaving the locked wallpaper group, editing its rules, or pinning content
  /// into it.
  groupSwitch,
}
