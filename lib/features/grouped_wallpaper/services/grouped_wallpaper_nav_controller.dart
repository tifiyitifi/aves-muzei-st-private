import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

/// Caches how the grouped wallpaper's bottom-bar entry is configured.
///
/// The bottom bar is built synchronously and must not read the database, so the
/// values are loaded once at startup and kept here; a change writes the database
/// and notifies every bar already on screen. This is fork-owned state, so it
/// lives in AppMeta rather than in the v1 settings store.
class GroupedWallpaperNavController extends ChangeNotifier {
  GroupedWallpaperNavMode _mode = defaultGroupedWallpaperNavMode;
  bool _entryClosed = false;

  GroupedWallpaperNavMode get mode => _mode;

  /// Whether the user closed the derived entry from a page's menu.
  bool get entryClosed => _entryClosed;

  /// Whether the bar should derive its own wallpaper entry.
  bool get derivesEntry => _mode != GroupedWallpaperNavMode.shared && !_entryClosed;

  Future<void> load() async {
    try {
      final store = WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());
      _mode = await store.readNavMode();
      _entryClosed = await store.readNavEntryClosed();
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to load the wallpaper navigation mode', error, stack);
    }
    notifyListeners();
  }

  /// Applies the change at once and persists it behind the UI: the bar is what
  /// the user is looking at, so it must not wait for a database round trip.
  Future<void> setMode(GroupedWallpaperNavMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _write((store) => store.writeNavMode(mode));
  }

  Future<void> setEntryClosed(bool closed) async {
    if (_entryClosed == closed) return;
    _entryClosed = closed;
    notifyListeners();
    await _write((store) => store.writeNavEntryClosed(closed));
  }

  Future<void> toggleEntryClosed() => setEntryClosed(!_entryClosed);

  Future<void> _write(Future<void> Function(WallpaperGroupStore store) write) async {
    try {
      await write(WallpaperGroupStore(await getIt<AppDatabaseProvider>().open()));
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to write the wallpaper navigation mode', error, stack);
    }
  }
}

/// The process-wide navigation-mode cache.
final groupedWallpaperNavController = GroupedWallpaperNavController();
