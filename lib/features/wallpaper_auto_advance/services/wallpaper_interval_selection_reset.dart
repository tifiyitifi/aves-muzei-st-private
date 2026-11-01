import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_bridge.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_prefs.dart';
import 'package:aves/features/wallpaper_auto_advance/log.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';

/// Applies a changed option list to the two independent selections.
///
/// [all] resets every group and the Muzei wallpaper; otherwise only the values
/// in [removed] are reset. [fallback] is the bundled reset target (off today).
typedef WallpaperIntervalSelectionReset = Future<void> Function({
  required Set<WallpaperAdvanceInterval> removed,
  required bool all,
  required WallpaperAdvanceInterval fallback,
});

/// Production fan-out of [WallpaperIntervalSelectionReset].
///
/// Each surface is isolated: a failing platform channel must not leave the other
/// wallpaper with a value that no longer exists in the list. The order is
/// catalog write → selections → schedules (the caller owns the catalog write).
Future<void> resetWallpaperIntervalSelections({
  required Set<WallpaperAdvanceInterval> removed,
  required bool all,
  required WallpaperAdvanceInterval fallback,
}) async {
  try {
    await wallpaperGroupController.resetIntervals(removed: removed, fallback: fallback, all: all);
  } catch (error, stack) {
    wallpaperAutoAdvanceLog.w('failed to reset grouped wallpaper intervals', error, stack);
  }
  try {
    await _resetMuzei(removed: removed, all: all, fallback: fallback);
  } catch (error, stack) {
    wallpaperAutoAdvanceLog.w('failed to reset Muzei wallpaper interval', error, stack);
  }
  try {
    // The engine is not attached while neither wallpaper page was opened; the
    // next sync then reads the saved group itself.
    await wallpaperEngineLink.refreshSchedule();
  } catch (error, stack) {
    wallpaperAutoAdvanceLog.w('failed to refresh the grouped wallpaper schedule', error, stack);
  }
}

Future<void> _resetMuzei({
  required Set<WallpaperAdvanceInterval> removed,
  required bool all,
  required WallpaperAdvanceInterval fallback,
}) async {
  await wallpaperPrefs.init();
  final selected = wallpaperPrefs.autoAdvance.interval;
  if (!all && !removed.contains(selected)) return;
  await wallpaperPrefs.setInterval(fallback);
  // `0` also cancels a stale chain when the wallpaper is not in use.
  final active = await WallpaperBridge.instance.isActive();
  await WallpaperBridge.instance.scheduleAutoAdvance(active ? fallback.seconds : 0);
}
