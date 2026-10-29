import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:flutter/widgets.dart';

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
    return ValueListenableBuilder<VisibleRangeDestination>(
      valueListenable: visibleRangeDestination,
      builder: (context, destination, _) => destination == VisibleRangeDestination.wallpaper
          ? GroupedWallpaperPage(selectCurrent: selectCurrentWallpaperGroup)
          : const VisibleRangePage(),
    );
  }
}
