import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the shared bottom-bar entry renders.
///
/// The sub-page choice is process-wide, so it survives a mode change and a
/// gesture cold start. In the shared mode the entry hosts both pages and follows
/// that choice; with a temporary wallpaper entry the range entry must never turn
/// into the wallpaper page, since the page has its own entry.
void main() {
  test('the shared mode follows the stored sub-page', () {
    for (final destination in VisibleRangeDestination.values) {
      expect(
        visibleRangeShellDestination(mode: GroupedWallpaperNavMode.shared, destination: destination),
        destination,
      );
    }
  });

  test('a temporary entry always shows the range page', () {
    for (final mode in [GroupedWallpaperNavMode.separateLeft, GroupedWallpaperNavMode.separateRight]) {
      for (final destination in VisibleRangeDestination.values) {
        expect(
          visibleRangeShellDestination(mode: mode, destination: destination),
          VisibleRangeDestination.range,
          reason: 'a stale destination must not take over the range entry in $mode',
        );
      }
    }
  });
}
