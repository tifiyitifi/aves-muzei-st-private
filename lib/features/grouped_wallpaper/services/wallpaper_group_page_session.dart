/// In-memory choice of the wallpaper group the page was showing.
///
/// The page is rebuilt whenever the shared bottom-bar entry is reopened, so the
/// selected group must outlive it: backgrounding the app keeps the choice, while
/// a process death resets it (the page then opens on the wallpaper's current
/// group again). Nothing here is persisted on purpose.
class WallpaperGroupPageSession {
  /// Whether the user has picked a group since the process started.
  bool initialized = false;

  /// The selected group id, or null for group 0.
  String? selectedGroupId;
}

/// The process-wide session, shared by every instance of the page.
final WallpaperGroupPageSession wallpaperGroupPageSession = WallpaperGroupPageSession();
