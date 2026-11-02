/// Whether the system lock screen actually draws this app's live wallpaper.
///
/// Android only reports the lock screen's live wallpaper separately from API 34,
/// so an older device cannot be inspected: [unknown] is the honest answer there.
/// The decoy fails closed — an unverifiable lock screen is treated as "not ours"
/// only for the warning, never as a reason to draw the home frame on it.
enum GroupedWallpaperLockSurfaceStatus {
  /// Our service is the lock screen's live wallpaper.
  ours,

  /// Another live wallpaper owns the lock screen.
  other,

  /// The lock screen has no live wallpaper (a static image, or the OEM does not
  /// support one).
  none,

  /// The platform cannot tell.
  unknown;

  static GroupedWallpaperLockSurfaceStatus parse(String? raw) {
    for (final status in values) {
      if (status.name == raw) return status;
    }
    return unknown;
  }

  /// Whether the decoy surface can be drawn on this device.
  bool get canDraw => this == ours;
}
