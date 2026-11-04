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

  /// Whether the wallpaper page's session is open.
  ///
  /// The session is the page's lifetime as the user experiences it, not the
  /// widget's: leaving the page for another bottom-bar destination keeps the
  /// entry and the group's browsing scope, because those are browsing state the
  /// user closes on purpose. Only the page's own "Close wallpaper page" action
  /// (or removing its entry in the navigation settings) ends it. The flag is
  /// deliberately in-memory, so a process restart starts closed.
  bool _sessionActive = false;

  GroupedWallpaperNavMode get mode => _mode;

  /// Whether the session is open, i.e. the page owns a bar entry and a scope.
  ///
  /// The bar derives the wallpaper entry only in this state (and never in the
  /// shared mode): opening the page from the visible range, a notification or a
  /// gesture adds the entry next to the visible range, and closing the session
  /// takes it away again.
  bool get sessionActive => _sessionActive;

  /// Whether the bar should derive its own wallpaper entry.
  bool get derivesEntry => _mode != GroupedWallpaperNavMode.shared && _sessionActive;

  /// Opens the session; the first open makes the entry appear.
  ///
  /// Idempotent: a page replaced by another one starts before the old disposes,
  /// and two opens must not need two closes.
  void openSession() {
    if (_sessionActive) return;
    _sessionActive = true;
    _notifyDeferred();
  }

  /// Closes the session; the entry goes away with it.
  void closeSession() {
    if (!_sessionActive) return;
    _sessionActive = false;
    _notifyDeferred();
  }

  /// Notifies after the current build instead of inside it.
  ///
  /// A session opens and closes while the Navigator builds its routes, when the
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
