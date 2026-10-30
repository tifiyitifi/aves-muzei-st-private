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
