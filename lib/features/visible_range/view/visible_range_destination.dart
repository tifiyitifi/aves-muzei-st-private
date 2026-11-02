import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The sub-page behind the shared bottom-bar entry.
///
/// Both pages are peers of one navigation destination: the entry keeps its route
/// (`/visible_range`) and renders whichever page is current. The choice is kept
/// in memory only, so backgrounding the app keeps it while a process death
/// falls back to the visible-range page — the user changes wallpaper less often
/// than the visible range.
enum VisibleRangeDestination {
  range,
  wallpaper,
}

/// The process-wide sub-page choice, defaulting to the visible-range page.
final ValueNotifier<VisibleRangeDestination> visibleRangeDestination = ValueNotifier(VisibleRangeDestination.range);

/// The page the shared entry actually renders.
///
/// The shared mode is off while the wallpaper page is its own navigation
/// destination: the entry always renders the visible-range page, so a stale
/// `wallpaper` value (a gesture cold start, a value stored by an older build) can
/// never turn the range entry into the wallpaper page. The enum, the notifier and
/// the shell stay in place while whether the shared entry ships again is open.
VisibleRangeDestination visibleRangeShellDestination({
  required GroupedWallpaperNavMode mode,
  required VisibleRangeDestination destination,
}) => VisibleRangeDestination.range;

/// The page the shared entry renders.
class VisibleRangeShellPage extends StatelessWidget {
  /// Whether the wallpaper page opens on the group the wallpaper is playing.
  ///
  /// The bottom-bar entry keeps the user's browsing session; a page opened as the
  /// backdrop of the wallpaper view must describe the group that is on screen
  /// instead, exactly like the view it sits under.
  final bool selectCurrentWallpaperGroup;

  const new({super.key, this.selectCurrentWallpaperGroup = false});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<GroupedWallpaperNavController, GroupedWallpaperNavMode>((v) => v.mode);
    return ValueListenableBuilder<VisibleRangeDestination>(
      valueListenable: visibleRangeDestination,
      builder: (context, destination, _) =>
          visibleRangeShellDestination(mode: mode, destination: destination) == VisibleRangeDestination.wallpaper ? GroupedWallpaperPage(selectCurrent: selectCurrentWallpaperGroup) : const VisibleRangePage(),
    );
  }
}
