import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_frame_retention.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_lock_surface_status.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_transition.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_capability.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';

/// What the page needs from the wallpaper engine.
///
/// The link depends on this interface instead of the engine class, so the page
/// never has to know how a frame is baked and a test can stand in for the engine.
abstract interface class WallpaperEngineConnection {
  /// Whether the grouped service is the current system wallpaper.
  Future<bool> isActive();

  /// Where the wallpaper is bound and whether the launcher can pan it.
  Future<WallpaperCapability> capability();

  /// Whether the wallpaper was in use and the system dropped it.
  Future<bool> restoreOffer();

  /// Whether the grouped wallpaper is explicitly turned off.
  Future<bool> isDisabled();

  /// The state the renderer is showing, or null when nothing was ever baked.
  Future<GroupedWallpaperState?> readState();

  /// [readState] moved to the slot the wallpaper engine is actually drawing.
  ///
  /// The renderer can promote a slot on its own, and a reload keeps drawing the
  /// slot it had, so `current` in `state.json` may name another photo than the
  /// one on screen. Surfaces that describe "the photo I am looking at" read this
  /// instead. [surface] selects the decoy frame when the group splits them.
  Future<GroupedWallpaperState?> readDisplayedState({WallpaperSurface surface});

  /// The state and the effect image on screen, read as one snapshot.
  ///
  /// The view page uses it so the title, the entry and the pixels it shows all
  /// describe the same frame, with the home or lock effect the renderer applied.
  Future<GroupedWallpaperDisplayedFrame?> readDisplayedFrame({WallpaperSurface surface});

  /// Absolute path of the sharp photo on screen, or null when there is none.
  Future<String?> currentPhotoPath({WallpaperSurface surface});

  /// Whether the system lock screen draws this app's live wallpaper.
  Future<GroupedWallpaperLockSurfaceStatus> lockSurfaceStatus();

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

  /// Records how many photos the usage history keeps.
  Future<void> setHistoryLimit(int limit);

  /// Records how a photo change is animated and applies it now.
  Future<void> setTransition(GroupedWallpaperTransition transition);

  /// Records how many baked frames the renderer keeps on the GPU.
  Future<void> setFrameRetention(GroupedWallpaperFrameRetention retention);

  /// Drops the rewind stack after the usage history was cleared.
  Future<void> clearRewind();

  /// Makes the wallpaper bar reflect the group-switch lock.
  Future<void> refreshLock();

  /// Shows the photo before the current one, when the history remembers one.
  Future<GroupedWallpaperSyncResult> previousArtwork();

  /// Shows the next photo of the group, resuming a frozen wallpaper first.
  Future<GroupedWallpaperSyncResult> nextArtwork();

  /// Steps the decoy lock surface to a new photo (the view page's action).
  Future<GroupedWallpaperSyncResult> nextLockArtwork();

  /// Steps the decoy lock surface back to a photo it already showed.
  Future<GroupedWallpaperSyncResult> previousLockArtwork();

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

  /// Where the wallpaper is bound and whether the launcher can pan it.
  ///
  /// A missing connection or a failing probe is [WallpaperCapability.unknown],
  /// which never narrows a frame.
  Future<WallpaperCapability> capability() async {
    final connection = _connection;
    if (connection == null) return WallpaperCapability.unknown;
    try {
      return await connection.capability();
    } catch (_) {
      return WallpaperCapability.unknown;
    }
  }

  /// Re-asks whether the wallpaper was in use and the system dropped it.
  ///
  /// The app asks on every return instead of trusting an older answer: the
  /// binding is lost while the app is away (an update), and it comes back when
  /// the user re-applies through the system chooser.
  Future<bool> refreshRestoreOffer() async {
    final connection = _connection;
    if (connection == null) return false;
    try {
      return await connection.restoreOffer();
    } catch (_) {
      // Without an answer there is nothing to offer: a wrong notice would send
      // the user to a picker that takes over a wallpaper they did not lose.
      return false;
    }
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

  Future<GroupedWallpaperState?> readState() async => await _connection?.readState();

  Future<GroupedWallpaperState?> readDisplayedState({WallpaperSurface surface = WallpaperSurface.home}) async => await _connection?.readDisplayedState(surface: surface);

  Future<GroupedWallpaperDisplayedFrame?> readDisplayedFrame({WallpaperSurface surface = WallpaperSurface.home}) async => await _connection?.readDisplayedFrame(surface: surface);

  Future<String?> currentPhotoPath({WallpaperSurface surface = WallpaperSurface.home}) async => await _connection?.currentPhotoPath(surface: surface);

  /// Whether the system lock screen draws this app's live wallpaper.
  Future<GroupedWallpaperLockSurfaceStatus> lockSurfaceStatus() async {
    try {
      return await _connection?.lockSurfaceStatus() ?? GroupedWallpaperLockSurfaceStatus.unknown;
    } catch (_) {
      return GroupedWallpaperLockSurfaceStatus.unknown;
    }
  }

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

  Future<void> setHistoryLimit(int limit) async => await _connection?.setHistoryLimit(limit);

  Future<void> setTransition(GroupedWallpaperTransition transition) async => await _connection?.setTransition(transition);

  Future<void> setFrameRetention(GroupedWallpaperFrameRetention retention) async => await _connection?.setFrameRetention(retention);

  Future<void> clearRewind() async => await _connection?.clearRewind();

  Future<void> refreshLock() async => await _connection?.refreshLock();

  Future<GroupedWallpaperSyncResult> previousArtwork() async => await _connection?.previousArtwork() ?? GroupedWallpaperSyncResult.notActive;

  Future<GroupedWallpaperSyncResult> nextArtwork() async => await _connection?.nextArtwork() ?? GroupedWallpaperSyncResult.notActive;

  Future<GroupedWallpaperSyncResult> nextLockArtwork() async => await _connection?.nextLockArtwork() ?? GroupedWallpaperSyncResult.notActive;

  Future<GroupedWallpaperSyncResult> previousLockArtwork() async => await _connection?.previousLockArtwork() ?? GroupedWallpaperSyncResult.notActive;

  Future<bool> openChooser() async => await _connection?.openChooser() ?? false;
}

/// The process-wide engine link.
final wallpaperEngineLink = WallpaperEngineLink();
