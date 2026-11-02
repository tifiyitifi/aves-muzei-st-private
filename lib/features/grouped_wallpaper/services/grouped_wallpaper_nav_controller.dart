import 'dart:async';

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

  /// How many wallpaper pages are on screen right now.
  ///
  /// The wallpaper page is a settings surface the user rarely opens, so the bar
  /// keeps it off by default and shows its entry only while the page is open.
  /// A depth counter (not a flag) keeps the entry alive across a page that is
  /// replaced by another one, where the new page starts before the old disposes.
  int _pageDepth = 0;

  GroupedWallpaperNavMode get mode => _mode;

  /// Whether the wallpaper page is on screen.
  ///
  /// The bar derives the wallpaper entry only in this state (and never in the
  /// shared mode): opening the page from the visible range, a notification or a
  /// gesture adds the entry next to the visible range, and closing the page
  /// takes it away again.
  bool get pageVisible => _pageDepth > 0;

  /// Whether the bar should derive its own wallpaper entry.
  bool get derivesEntry => _mode != GroupedWallpaperNavMode.shared && pageVisible;

  /// Marks a wallpaper page as opened; the first one makes the entry appear.
  void enterPage() {
    _pageDepth++;
    if (_pageDepth == 1) _notifyDeferred();
  }

  /// Marks a wallpaper page as closed; the entry goes away with the last one.
  void exitPage() {
    if (_pageDepth == 0) return;
    _pageDepth--;
    if (_pageDepth == 0) _notifyDeferred();
  }

  /// Notifies after the current build instead of inside it.
  ///
  /// A page enters and leaves while the Navigator builds its routes, when the
  /// bottom bar may already have been built this frame; marking it dirty there
  /// would throw "setState() or markNeedsBuild() called during build". A
  /// microtask runs as soon as the synchronous frame work returns.
  void _notifyDeferred() => scheduleMicrotask(notifyListeners);

  Future<void> load() async {
    try {
      final store = WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());
      _mode = await store.readNavMode();
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
