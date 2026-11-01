import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/db/wallpaper_interval_options_store.dart';
import 'package:aves/features/wallpaper_auto_advance/log.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_selection_reset.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

/// Owns the shared interval option list and the management actions on it.
///
/// The selected value is not here: every group stores its own interval and the
/// Muzei wallpaper stores another, so this controller never changes a selection
/// except through [WallpaperIntervalSelectionReset] after a deletion.
class WallpaperIntervalOptionsController extends ChangeNotifier {
  /// Optional injected database, used by tests (which never register the
  /// app-wide [AppDatabaseProvider]).
  final AppDatabase? injectedDatabase;

  /// Loads the bundled defaults. Injectable so tests never read assets.
  final Future<WallpaperIntervalDefaults> Function() bundledLoader;

  /// Applies a removed-or-cleared interval to the two selections.
  ///
  /// Injected so the controller can be tested without touching the wallpaper
  /// engines; production uses [resetWallpaperIntervalSelections].
  final WallpaperIntervalSelectionReset selectionReset;

  WallpaperIntervalOptionsStore? _store;
  WallpaperIntervalCatalog? _catalog;
  Future<void>? _loadFuture;
  bool _disposed = false;

  new({
    this.injectedDatabase,
    Future<WallpaperIntervalDefaults> Function()? bundledLoader,
    WallpaperIntervalSelectionReset? selectionReset,
  })  : bundledLoader = bundledLoader ?? loadWallpaperIntervalDefaults,
        selectionReset = selectionReset ?? resetWallpaperIntervalSelections;

  WallpaperIntervalCatalog? get catalog => _catalog;

  bool get isLoaded => _catalog != null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the catalog once; concurrent callers share the same future.
  Future<void> ensureLoaded() => _loadFuture ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final store = _store ??= WallpaperIntervalOptionsStore(
        injectedDatabase ?? await getIt<AppDatabaseProvider>().open(),
        bundledLoader: bundledLoader,
      );
      _catalog = await store.loadOrSeed();
    } catch (error, stack) {
      // A broken database must not hide the page: show the bundled list and let
      // the next action try to persist again.
      wallpaperAutoAdvanceLog.e('failed to load the interval options', error, stack);
      _catalog = WallpaperIntervalCatalog.seeded(await bundledLoader());
    }
    _notify();
  }

  /// Adds [value] if it is new and returns the option to select.
  ///
  /// A value that is a shipped built-in but currently missing is restored as a
  /// built-in instead of becoming a deletable custom option, so 「Add default
  /// intervals」 and a manual add agree on what is built in.
  Future<WallpaperAdvanceInterval> addCustom(WallpaperAdvanceInterval value) async {
    await ensureLoaded();
    final catalog = _catalog!;
    final interval = WallpaperAdvanceInterval.fromSeconds(value.seconds);
    if (catalog.contains(interval)) return interval;
    final isShipped = catalog.shippedDefaults.contains(interval);
    await _write(
      isShipped
          ? catalog.copyWith(defaults: sorted([...catalog.defaults, interval]))
          : catalog.copyWith(customs: sorted([...catalog.customs, interval])),
    );
    return interval;
  }

  /// Deletes any of [removed] from the list, built-in or custom.
  ///
  /// Off is pinned: it is the only way to turn auto-advance back off and the
  /// value every reset falls back to, so it is always dropped from [removed].
  /// A deleted built-in stays recoverable through [addMissingDefaults].
  ///
  /// Only groups and the Muzei wallpaper currently using one of the deleted
  /// values are reset; everything else keeps its selection.
  Future<void> deleteOptions(Set<WallpaperAdvanceInterval> removed) async {
    final targets = {...removed}..remove(WallpaperAdvanceInterval.off);
    if (targets.isEmpty) return;
    await ensureLoaded();
    final catalog = _catalog!;
    await _write(catalog.copyWith(
      defaults: [for (final value in catalog.defaults) if (!targets.contains(value)) value],
      customs: [for (final value in catalog.customs) if (!targets.contains(value)) value],
    ));
    await selectionReset(removed: targets, all: false, fallback: catalog.defaultInterval);
  }

  /// Clears every option except Off and leaves every selection alone.
  ///
  /// Clearing Off too would make a later add produce a list with no off switch
  /// at all, so the pinned option survives as the only built-in left; 「Add
  /// default intervals」 then restores the rest. The pickers keep showing the
  /// caller's current value as an extra option, so clearing never silently
  /// changes what a group plays. This is the list-only half of [resetToDefaults].
  Future<void> clearList() async {
    await ensureLoaded();
    final catalog = _catalog!;
    await _write(catalog.copyWith(defaults: const [WallpaperAdvanceInterval.off], customs: const []));
  }

  /// Restores the shipped list and turns every wallpaper off.
  ///
  /// The factory reset: custom options are dropped, the bundled built-ins come
  /// back, and each group plus the Muzei wallpaper return to the bundled default
  /// (off today). 「Add default intervals」 is the additive alternative.
  Future<void> resetToDefaults() async {
    await ensureLoaded();
    final catalog = _catalog!;
    await _write(catalog.copyWith(
      defaults: sorted(catalog.shippedDefaults),
      customs: const [],
    ));
    await selectionReset(removed: const {}, all: true, fallback: catalog.defaultInterval);
  }

  /// Restores the shipped built-ins that are currently missing.
  ///
  /// Deliberately additive: custom options and every selection stay untouched,
  /// which is what makes this the recovery path after a Reset.
  Future<void> addMissingDefaults() async {
    await ensureLoaded();
    final catalog = _catalog!;
    final missing = catalog.missingDefaults;
    if (missing.isEmpty) return;
    await _write(catalog.copyWith(defaults: sorted([...catalog.defaults, ...missing])));
  }

  Future<void> _write(WallpaperIntervalCatalog catalog) async {
    _catalog = catalog;
    try {
      await (_store ??= WallpaperIntervalOptionsStore(
        injectedDatabase ?? await getIt<AppDatabaseProvider>().open(),
        bundledLoader: bundledLoader,
      )).write(catalog);
    } catch (error, stack) {
      // Keep the in-memory list usable; a later action retries the write.
      wallpaperAutoAdvanceLog.w('failed to persist the interval options', error, stack);
    }
    _notify();
  }
}

/// The app-wide option list, shared by the grouped and Muzei auto-advance pages.
final wallpaperIntervalOptionsController = WallpaperIntervalOptionsController();
