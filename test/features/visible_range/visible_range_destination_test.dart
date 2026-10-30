import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the shared bottom-bar entry renders.
///
/// The sub-page choice is process-wide, so it survives a mode change and a
/// gesture cold start. In a separate mode the wallpaper page has its own entry,
/// and the range entry must never turn into it: that made the two entries show
/// the same page and looked like the range entry opened the wrong one.
void main() {
  test('a separate mode always shows the range page', () {
    for (final mode in [GroupedWallpaperNavMode.separateLeft, GroupedWallpaperNavMode.separateRight]) {
      expect(
        visibleRangeShellDestination(mode: mode, destination: VisibleRangeDestination.wallpaper),
        VisibleRangeDestination.range,
        reason: 'a stale destination must not take over the range entry in $mode',
      );
      expect(visibleRangeShellDestination(mode: mode, destination: VisibleRangeDestination.range), VisibleRangeDestination.range);
    }
  });

  test('the shared mode flips between the two pages', () {
    expect(visibleRangeShellDestination(mode: GroupedWallpaperNavMode.shared, destination: VisibleRangeDestination.wallpaper), VisibleRangeDestination.wallpaper);
    expect(visibleRangeShellDestination(mode: GroupedWallpaperNavMode.shared, destination: VisibleRangeDestination.range), VisibleRangeDestination.range);
  });
}
