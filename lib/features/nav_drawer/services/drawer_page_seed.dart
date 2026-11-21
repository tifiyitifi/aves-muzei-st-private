import 'package:aves/features/nav_drawer/log.dart';
import 'package:aves/features/nav_drawer/model/drawer_page_keys.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time backfill of the drawer page list.
///
/// Before the fork pages became editable, the visible range was a fixed drawer
/// tile: it could be neither removed nor added, so a list the user saved back
/// then lacks it. Without the backfill, upgrading would silently remove the
/// entry. The marker in [DrawerPageKeys] keeps it one-time, so a later removal is
/// respected as the user's decision.
class DrawerPageSeed {
  final Future<SharedPreferences> Function() _prefsProvider;

  new({Future<SharedPreferences> Function()? prefsProvider}) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  Future<void> runIfNeeded({required bool useTvLayout}) async {
    try {
      final prefs = await _prefsProvider();
      if (prefs.getBool(DrawerPageKeys.forkPagesInitialized) ?? false) return;
      // The TV rail keeps its own list, written by `applyTvSettings`: the fixed
      // drawer tile this backfill describes never existed there.
      if (!useTvLayout) {
        final stored = settings.getStringList(SettingKeys.drawerPageBookmarksKey);
        if (stored != null) {
          final next = withLegacyVisibleRange(stored);
          if (!listEquals(next, stored)) {
            // Wait for the list before writing the marker. The store write is
            // asynchronous (a database put in v2); a failed or interrupted
            // backfill must be retried on the next launch instead of being
            // recorded as done.
            final written = await settings.store.setStringList(SettingKeys.drawerPageBookmarksKey, next);
            if (!written) {
              navDrawerLog.w('failed to backfill the drawer page list; will retry');
              return;
            }
            settings.notifyKeyChange(SettingKeys.drawerPageBookmarksKey, stored, next, recordRecent: false);
            settings.notifyListeners();
            navDrawerLog.i('backfilled the visible-range drawer entry');
          }
        }
      }
      await prefs.setBool(DrawerPageKeys.forkPagesInitialized, true);
    } catch (error, stack) {
      // A drawer that keeps one extra entry is harmless; a failed startup is not.
      navDrawerLog.e('failed to seed the drawer pages', error, stack);
    }
  }

  /// Records that the user has seen the editable list.
  ///
  /// Called by the drawer editor, so a list saved without the visible range is
  /// read as a removal and is never backfilled again.
  Future<void> markConfigured() async {
    try {
      final prefs = await _prefsProvider();
      if (prefs.getBool(DrawerPageKeys.forkPagesInitialized) ?? false) return;
      await prefs.setBool(DrawerPageKeys.forkPagesInitialized, true);
    } catch (error, stack) {
      navDrawerLog.e('failed to mark the drawer pages as configured', error, stack);
    }
  }
}

/// Puts the visible range where its fixed tile used to sit: before Explorer, else
/// at the end.
///
/// Idempotent, so it can be applied to a list that already has the entry.
List<String> withLegacyVisibleRange(List<String> pages) {
  if (pages.contains(VisibleRangePage.routeName)) return pages;
  final explorer = pages.indexOf(ExplorerPage.routeName);
  final index = explorer >= 0 ? explorer : pages.length;
  return [...pages.sublist(0, index), VisibleRangePage.routeName, ...pages.sublist(index)];
}

/// The process-wide seed; the composition root runs it once per launch.
final drawerPageSeed = DrawerPageSeed();
