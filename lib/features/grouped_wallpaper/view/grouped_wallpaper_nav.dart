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
/// `bottomNavigationActions`: the entry is derived at build time.
///
/// - The wallpaper entry follows its **session** ([sessionActive]): it appears
///   when the page is opened from the visible range, a notification or a
///   gesture, and stays after the user leaves for another destination. Only
///   closing the page (its own action, or removing the entry in the navigation
///   settings) ends the session and takes the entry away.
/// - A user who added `/wallpaper_groups` themselves owns the entry, so no second
///   one is derived ("pinned").
/// - [GroupedWallpaperNavMode.shared] keeps the single shell entry, which flips
///   between the two pages instead of adding one.
/// - [include] is false while picking a photo, where a fork destination has no
///   meaning; the list is then returned untouched, like the range entry.
List<AvesNavItem> withWallpaperNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool sessionActive,
  bool include = true,
}) {
  if (!include) return configured;
  final items = withVisibleRangeDestination(configured);
  if (mode == GroupedWallpaperNavMode.shared || !sessionActive) return items;
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

/// The destinations the bar adds on its own, on top of the user's own list.
///
/// The navigation editor lists `bottomNavigationActions` as editable buttons and
/// has to describe the bar the user actually sees, so the difference is shown
/// read-only instead of silently missing. Order is kept: it is where the bar
/// puts them.
///
/// The range entry is always derived and permanent. The wallpaper entry is
/// listed while its session is open (and never in the shared mode, which derives
/// none): removing it there is the same close as the page's own action, so the
/// editor can offer it.
List<AvesNavItem> derivedNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool sessionActive,
}) {
  final effective = withWallpaperNavDestinations(configured, mode: mode, sessionActive: sessionActive);
  return effective.where((item) => !configured.contains(item)).toList();
}
