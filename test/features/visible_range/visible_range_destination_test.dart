import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the shared bottom-bar entry renders.
///
/// The sub-page choice is process-wide, so it survives a mode change and a
/// gesture cold start. In the shared mode the entry hosts the pages and follows
/// that choice; with a temporary wallpaper entry the range entry must never turn
/// into the wallpaper page, since the page has its own entry. The editor page is
/// the editor's session: without one, the entry falls back to the range page.
void main() {
  tearDown(visibleRangeEditorSession.close);

  test('the shared mode follows the stored sub-page', () {
    for (final destination in VisibleRangeDestination.values) {
      visibleRangeEditorSession.open('group.test', VisibleRange.emptyGallery());
      expect(
        visibleRangeShellDestination(mode: GroupedWallpaperNavMode.shared, destination: destination),
        destination,
      );
      visibleRangeEditorSession.close();
    }
  });

  test('a closed editor session falls back to the range page', () {
    expect(
      visibleRangeShellDestination(mode: GroupedWallpaperNavMode.shared, destination: VisibleRangeDestination.editor),
      VisibleRangeDestination.range,
    );
  });

  test('a separate entry always shows the range page', () {
    for (final mode in [GroupedWallpaperNavMode.separateLeft, GroupedWallpaperNavMode.separateRight]) {
      for (final destination in VisibleRangeDestination.values) {
        visibleRangeEditorSession.open('group.test', VisibleRange.emptyGallery());
        expect(
          visibleRangeShellDestination(mode: mode, destination: destination),
          VisibleRangeDestination.range,
          reason: 'a stale destination must not take over the range entry in $mode',
        );
        visibleRangeEditorSession.close();
      }
    }
  });
}

