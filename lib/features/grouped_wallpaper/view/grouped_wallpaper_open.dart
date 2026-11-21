import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:material_ui/material_ui.dart';

/// Where a request to open the wallpaper groups goes.
///
/// The visible range's menu and the drawer both ask for "the wallpaper page", so
/// they share this decision: in the shared mode the page lives behind the single
/// range entry, and opening a second entry would duplicate the page the shell
/// already hosts.
enum GroupedWallpaperOpen {
  /// The shared entry is on screen: only flip its sub-page.
  flipSharedEntry,

  /// The shared entry is the destination, opened on the wallpaper page.
  openSharedEntry,

  /// The wallpaper page is a destination of its own.
  openWallpaperPage,
}

GroupedWallpaperOpen groupedWallpaperOpen({
  required GroupedWallpaperNavMode mode,
  required bool sharedEntryOnTop,
}) {
  if (mode != GroupedWallpaperNavMode.shared) return GroupedWallpaperOpen.openWallpaperPage;
  return sharedEntryOnTop ? GroupedWallpaperOpen.flipSharedEntry : GroupedWallpaperOpen.openSharedEntry;
}

/// Opens the wallpaper groups exactly like the visible range's menu does.
///
/// The drawer's own grouped-wallpaper entry routes through here instead of
/// pushing its route directly, so both entry points cannot disagree about the
/// shared mode. The page opens as a destination of its own, which is also what
/// its close action expects.
Future<void> openGroupedWallpaperGroups(BuildContext context) async {
  final open = groupedWallpaperOpen(
    mode: groupedWallpaperNavController.mode,
    sharedEntryOnTop: ModalRoute.of(context)?.settings.name == VisibleRangePage.routeName,
  );
  switch (open) {
    case GroupedWallpaperOpen.flipSharedEntry:
      visibleRangeDestination.value = VisibleRangeDestination.wallpaper;
    case GroupedWallpaperOpen.openSharedEntry:
      visibleRangeDestination.value = VisibleRangeDestination.wallpaper;
      await const AvesNavItem(route: VisibleRangePage.routeName).goTo(context, topLevel: true);
    case GroupedWallpaperOpen.openWallpaperPage:
      await const AvesNavItem(route: GroupedWallpaperPage.routeName).goTo(context, topLevel: true);
  }
}
