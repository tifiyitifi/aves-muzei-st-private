import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';

/// What the page needs from the wallpaper engine.
///
/// The link depends on this interface instead of the engine class, so the page
/// never has to know how a frame is baked and a test can stand in for the engine.
abstract interface class WallpaperEngineConnection {
  /// Whether the grouped service is the current system wallpaper.
  Future<bool> isActive();

  /// The state the renderer is showing, or null when nothing was ever baked.
  Future<GroupedWallpaperState?> readState();

  /// Re-bakes the saved current group and applies it now.
  Future<GroupedWallpaperSyncResult> syncNow();

  /// Opens the system live-wallpaper chooser for this service.
  Future<bool> openChooser();
}

/// The grouped wallpaper engine's hook into the page.
///
/// [isActive] is cached because the page's menu is built synchronously:
/// [refreshActive] re-probes when the page opens or resumes. Until the engine is
/// attached the entries stay greyed out with a reason, never a silent success.
class WallpaperEngineLink {
  WallpaperEngineConnection? _connection;
  bool _active = false;

  /// Whether the engine is wired to the platform channel.
  bool get isAttached => _connection != null;

  /// Whether the grouped wallpaper is the system wallpaper, as of the last
  /// [refreshActive].
  bool get isActive => isAttached && _active;

  void attach(WallpaperEngineConnection connection) {
    _connection = connection;
  }

  void detach() {
    _connection = null;
    _active = false;
  }

  /// Re-reads whether the grouped service is the current system wallpaper.
  Future<bool> refreshActive() async {
    final connection = _connection;
    if (connection == null) {
      _active = false;
      return false;
    }
    try {
      _active = await connection.isActive();
    } catch (_) {
      // A failed probe is "not active": the page then explains why instead of
      // offering a sync that cannot apply anything.
      _active = false;
    }
    return _active;
  }

  Future<GroupedWallpaperState?> readState() async => await _connection?.readState();

  Future<GroupedWallpaperSyncResult> syncNow() async => await _connection?.syncNow() ?? GroupedWallpaperSyncResult.notActive;

  Future<bool> openChooser() async => await _connection?.openChooser() ?? false;
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
