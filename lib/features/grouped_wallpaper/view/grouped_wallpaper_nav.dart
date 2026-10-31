import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_nav.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';

/// The bottom-bar destinations a surface should show.
///
/// The visible-range entry is appended first, then the grouped wallpaper's entry
/// is placed immediately left or right of it, so the two peers stay adjacent no
/// matter where the user put the range entry. Nothing is written into the user's
/// `bottomNavigationActions`: the entry is derived at build time, which is also
/// what lets it be closed from the page's menu.
///
/// - A user who added `/wallpaper_groups` themselves owns the entry, so no second
///   one is derived ("pinned").
/// - [GroupedWallpaperNavMode.shared] keeps the single shell entry, and
///   [entryClosed] hides the derived one; the range entry is still appended.
/// - [include] is false while picking a photo, where a fork destination has no
///   meaning; the list is then returned untouched, like the range entry.
List<AvesNavItem> withWallpaperNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool entryClosed,
  bool include = true,
}) {
  if (!include) return configured;
  final items = withVisibleRangeDestination(configured);
  if (mode == GroupedWallpaperNavMode.shared || entryClosed) return items;
  if (items.any((item) => item.route == GroupedWallpaperPage.routeName)) return items;

  final rangeIndex = items.indexWhere((item) => item.route == VisibleRangePage.routeName);
  // The range entry is appended by the call above, so this is only a guard for
  // a future change there; the wallpaper entry then goes last.
  if (rangeIndex < 0) return [...items, const AvesNavItem(route: GroupedWallpaperPage.routeName)];

  final index = mode == GroupedWallpaperNavMode.separateLeft ? rangeIndex : rangeIndex + 1;
  return [
    ...items.sublist(0, index),
    const AvesNavItem(route: GroupedWallpaperPage.routeName),
    ...items.sublist(index),
  ];
}

/// Whether the derived wallpaper entry is hidden and can be brought back.
///
/// Closing the entry sends the user back to the visible range page, so that page
/// owns the way back: without it the only control would live on the page the
/// missing entry leads to. A pinned entry belongs to the user's own list and is
/// managed in the navigation editor instead, and the shared mode has no derived
/// entry to close.
bool canReopenWallpaperNavEntry({
  required GroupedWallpaperNavMode mode,
  required bool entryClosed,
  required bool pinned,
}) =>
    mode != GroupedWallpaperNavMode.shared && entryClosed && !pinned;

/// What the visible-range page's single wallpaper entry offers.
///
/// The page used to list "open the groups" and "bring the entry back" as two
/// items, which read as duplicates; they are one toggle now. [close] is the only
/// alternative to [open]: either the bar's derived entry is shown, so the menu
/// hides it, or it is gone, so the menu brings it back.
enum WallpaperNavEntryAction {
  /// Shows the wallpaper page, reopening its bar entry if it was closed.
  open,

  /// Hides the bar's derived wallpaper entry.
  close,
}

/// The action behind the visible-range page's merged wallpaper entry.
///
/// A pinned entry belongs to the user's own list and is managed in the
/// navigation editor, so this menu never hides it; the shared mode has no
/// derived entry either, so both modes always open.
WallpaperNavEntryAction wallpaperNavEntryAction({
  required GroupedWallpaperNavMode mode,
  required bool entryClosed,
  required bool pinned,
}) {
  if (canReopenWallpaperNavEntry(mode: mode, entryClosed: entryClosed, pinned: pinned)) return WallpaperNavEntryAction.open;
  // The derived entry is on the bar, so the menu offers to hide it.
  if (mode != GroupedWallpaperNavMode.shared && !pinned) return WallpaperNavEntryAction.close;
  return WallpaperNavEntryAction.open;
}

/// The destinations the bar adds on its own, on top of the user's own list.
///
/// The navigation editor lists `bottomNavigationActions` as editable buttons and
/// has to describe the bar the user actually sees, so the difference is shown
/// read-only instead of silently missing. Order is kept: it is where the bar
/// puts them.
List<AvesNavItem> derivedNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool entryClosed,
}) {
  final effective = withWallpaperNavDestinations(configured, mode: mode, entryClosed: entryClosed);
  return effective.where((item) => !configured.contains(item)).toList();
}
