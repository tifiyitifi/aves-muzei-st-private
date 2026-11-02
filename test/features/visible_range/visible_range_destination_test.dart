import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the shared bottom-bar entry renders.
///
/// The shared mode is off while the wallpaper page is its own navigation
/// destination: the range entry always renders the range page, whatever sub-page
/// a stale value names.
void main() {
  test('the range entry always shows the range page', () {
    for (final mode in GroupedWallpaperNavMode.values) {
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
