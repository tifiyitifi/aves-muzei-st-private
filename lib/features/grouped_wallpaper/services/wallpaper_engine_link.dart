import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';

/// What the page needs from the wallpaper engine.
///
/// The link depends on this interface instead of the engine class, so the page
/// never has to know how a frame is baked and a test can stand in for the engine.
abstract interface class WallpaperEngineConnection {
  /// Whether the grouped service is the current system wallpaper.
  Future<bool> isActive();

  /// Whether the grouped wallpaper is explicitly turned off.
  Future<bool> isDisabled();

  /// The state the renderer is showing, or null when nothing was ever baked.
  Future<GroupedWallpaperState?> readState();

  /// Absolute path of the photo on screen, or null when there is none.
  Future<String?> currentPhotoPath();

  /// Absolute path of the home-effect image of the photo on screen.
  ///
  /// This is what the view page shows: the wallpaper's own pixels, effects
  /// included. The effects editor uses [currentPhotoPath] instead, because it
  /// applies the effect to the sharp image itself.
  Future<String?> currentEffectPhotoPath();

  /// Keeps a frame ready for the saved group, without requiring the service to
  /// be the system wallpaper yet.
  Future<GroupedWallpaperSyncResult> prepare({bool activation = false});

  /// Re-bakes the saved current group and applies it now.
  Future<GroupedWallpaperSyncResult> syncNow();

  /// Records the explicit off/on switch without touching the current group.
  Future<void> setDisabled(bool disabled);

  /// Opens the system live-wallpaper chooser for this service.
  Future<bool> openChooser();
}

/// The grouped wallpaper engine's hook into the page.
///
/// [isActive] and [isDisabled] are cached because the page's menu is built
/// synchronously: [refreshActive] re-probes when the page opens or resumes.
/// Until the engine is attached the entries stay greyed out with a reason, never
/// a silent success.
class WallpaperEngineLink {
  WallpaperEngineConnection? _connection;
  bool _active = false;
  bool _disabled = false;

  /// Whether the engine is wired to the platform channel.
  bool get isAttached => _connection != null;

  /// Whether the grouped wallpaper is the system wallpaper, as of the last
  /// [refreshActive].
  bool get isActive => isAttached && _active;

  /// Whether the grouped wallpaper is explicitly turned off.
  bool get isDisabled => _disabled;

  /// Whether the grouped wallpaper is on screen and following its group.
  ///
  /// A disabled feature keeps its last frame, so it is not "playing" even while
  /// its service is still the system wallpaper.
  bool get isPlaying => isActive && !_disabled;

  void attach(WallpaperEngineConnection connection) {
    _connection = connection;
  }

  void detach() {
    _connection = null;
    _active = false;
    _disabled = false;
  }

  /// Re-reads whether the grouped service is the current system wallpaper and
  /// whether the feature is turned on.
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

  /// Re-reads the explicit off switch, which the page may have just written.
  Future<void> refreshDisabled() async {
    final connection = _connection;
    if (connection == null) {
      _disabled = false;
      return;
    }
    try {
      _disabled = await connection.isDisabled();
    } catch (_) {
      // An unreadable flag is "on": the engine itself re-reads the saved value
      // before it bakes anything.
      _disabled = false;
    }
  }

  Future<GroupedWallpaperState?> readState() async => await _connection?.readState();

  Future<String?> currentPhotoPath() async => await _connection?.currentPhotoPath();

  Future<String?> currentEffectPhotoPath() async => await _connection?.currentEffectPhotoPath();

  Future<GroupedWallpaperSyncResult> prepare() async => await _connection?.prepare() ?? GroupedWallpaperSyncResult.notActive;

  Future<GroupedWallpaperSyncResult> syncNow() async => await _connection?.syncNow() ?? GroupedWallpaperSyncResult.notActive;

  Future<void> setDisabled(bool disabled) async {
    await _connection?.setDisabled(disabled);
    _disabled = disabled;
  }

  Future<bool> openChooser() async => await _connection?.openChooser() ?? false;
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
