import 'dart:async';

/// The grouped wallpaper engine's hook into the page.
///
/// The engine attaches here when its platform channel is available, so 「Sync
/// wallpaper now」 applies the saved groups immediately instead of waiting for
/// the wallpaper's interval. [isActive] is cached because the page's menu is
/// built synchronously: [refreshActive] re-probes when the page opens or resumes.
/// Until the engine is attached the entry stays greyed out with a reason, never a
/// silent success.
class WallpaperEngineLink {
  Future<void> Function()? _syncNow;
  Future<bool> Function()? _probeActive;
  bool _active = false;

  /// Whether the engine is wired to the platform channel.
  bool get isAttached => _syncNow != null;

  /// Whether the grouped wallpaper is the system wallpaper, as of the last
  /// [refreshActive].
  bool get isActive => isAttached && _active;

  void attach({
    required Future<void> Function() syncNow,
    required Future<bool> Function() isActive,
  }) {
    _syncNow = syncNow;
    _probeActive = isActive;
  }

  void detach() {
    _syncNow = null;
    _probeActive = null;
    _active = false;
  }

  /// Re-reads whether the grouped service is the current system wallpaper.
  Future<bool> refreshActive() async {
    final probe = _probeActive;
    if (probe == null) {
      _active = false;
      return false;
    }
    try {
      _active = await probe();
    } catch (_) {
      // A failed probe is "not active": the page then explains why instead of
      // offering a sync that cannot apply anything.
      _active = false;
    }
    return _active;
  }

  /// Asks the running engine to re-bake and apply the saved state immediately.
  Future<void> syncNow() async {
    final sync = _syncNow;
    if (sync != null) await sync();
  }
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
