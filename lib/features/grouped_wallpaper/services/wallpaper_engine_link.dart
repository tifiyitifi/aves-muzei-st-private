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

  /// Re-applies the current group's auto-advance interval to the scheduler.
  Future<void> refreshSchedule();

  /// Records the explicit off/on switch without touching the current group.
  Future<void> setDisabled(bool disabled);

  /// Whether the wallpaper may show its notification bar.
  Future<bool> isNotificationEnabled();

  /// Records the notification bar switch and applies it now.
  Future<void> setNotification(bool enabled);

  /// Whether frames keep the photo's whole width for the launcher to pan.
  Future<bool> isScrollEffectEnabled();

  /// Records the scroll effect switch and re-bakes the frame on screen.
  Future<void> setScrollEffect(bool enabled);

  /// Records how many photos the usage history keeps.
  Future<void> setHistoryLimit(int limit);

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
  bool _notification = true;
  bool _scrollEffect = true;

  /// Whether the engine is wired to the platform channel.
  bool get isAttached => _connection != null;

  /// Whether the grouped wallpaper is the system wallpaper, as of the last
  /// [refreshActive].
  bool get isActive => isAttached && _active;

  /// Whether the grouped wallpaper is explicitly turned off.
  bool get isDisabled => _disabled;

  /// Whether the wallpaper may show its notification bar, as of the last
  /// [refreshNotification].
  bool get notificationEnabled => _notification;

  /// Whether frames keep the photo's whole width, as of the last
  /// [refreshScrollEffect].
  bool get scrollEffectEnabled => _scrollEffect;

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
    _scrollEffect = true;
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

  /// Re-reads the notification bar switch.
  Future<void> refreshNotification() async {
    final connection = _connection;
    if (connection == null) {
      _notification = true;
      return;
    }
    try {
      _notification = await connection.isNotificationEnabled();
    } catch (_) {
      // An unreadable flag is "on", like the off switch above.
      _notification = true;
    }
  }

  /// Re-reads the scroll effect switch.
  Future<void> refreshScrollEffect() async {
    final connection = _connection;
    if (connection == null) {
      _scrollEffect = true;
      return;
    }
    try {
      _scrollEffect = await connection.isScrollEffectEnabled();
    } catch (_) {
      // An unreadable flag is "on", like the switches above.
      _scrollEffect = true;
    }
  }

  Future<GroupedWallpaperState?> readState() async => await _connection?.readState();

  Future<String?> currentPhotoPath() async => await _connection?.currentPhotoPath();

  Future<String?> currentEffectPhotoPath() async => await _connection?.currentEffectPhotoPath();

  Future<GroupedWallpaperSyncResult> prepare() async => await _connection?.prepare() ?? GroupedWallpaperSyncResult.notActive;

  Future<GroupedWallpaperSyncResult> syncNow() async => await _connection?.syncNow() ?? GroupedWallpaperSyncResult.notActive;

  Future<void> refreshSchedule() async => await _connection?.refreshSchedule();

  Future<void> setDisabled(bool disabled) async {
    await _connection?.setDisabled(disabled);
    _disabled = disabled;
  }

  Future<void> setNotification(bool enabled) async {
    await _connection?.setNotification(enabled);
    _notification = enabled;
  }

  Future<void> setScrollEffect(bool enabled) async {
    await _connection?.setScrollEffect(enabled);
    _scrollEffect = enabled;
  }

  Future<void> setHistoryLimit(int limit) async => await _connection?.setHistoryLimit(limit);

  Future<bool> openChooser() async => await _connection?.openChooser() ?? false;
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
