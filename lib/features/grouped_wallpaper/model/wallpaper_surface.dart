/// The two places the grouped wallpaper can draw.
///
/// [lock] is a decoy surface: it exists so that whoever sees the lock screen
/// does not learn which group the home screen is playing. It therefore has its
/// own visible range, its own history entries and its own single baked frame,
/// and it advances only with time (no gesture), because its job is to look like
/// the public group while the private one stays on the home screen.
enum WallpaperSurface {
  home,
  lock;

  /// Persisted by name: the database and `state.json` must not depend on the
  /// declaration order.
  static WallpaperSurface parse(String? raw) => raw == lock.name ? lock : home;

  bool get isLock => this == lock;
}
