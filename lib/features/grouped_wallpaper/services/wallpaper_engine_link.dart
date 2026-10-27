import 'dart:async';

/// The grouped wallpaper engine's hook into the settings page.
///
/// The engine is a separate phase: when it is the active system wallpaper it
/// attaches here, so 「Sync wallpaper now」 applies the saved groups immediately
/// instead of waiting for the wallpaper's interval. Until then the page shows
/// the entry greyed out with a reason, never a silent success.
class WallpaperEngineLink {
  Future<void> Function()? _syncNow;

  /// Whether a grouped wallpaper engine is running and can apply a sync now.
  bool get isActive => _syncNow != null;

  void attach({required Future<void> Function() syncNow}) {
    _syncNow = syncNow;
  }

  void detach() {
    _syncNow = null;
  }

  /// Asks the running engine to re-bake and apply the saved state immediately.
  Future<void> syncNow() async {
    final sync = _syncNow;
    if (sync != null) await sync();
  }
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
