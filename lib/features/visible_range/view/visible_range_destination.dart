import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_group_editor_page.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The sub-page behind the shared bottom-bar entry.
///
/// The pages are peers of one navigation destination: the entry keeps its route
/// (`/visible_range`) and renders whichever page is current. The choice is kept
/// in memory only, so backgrounding the app keeps it while a process death
/// falls back to the visible-range page.
enum VisibleRangeDestination {
  range,
  wallpaper,
  editor,
}

/// The process-wide sub-page choice, defaulting to the visible-range page.
final ValueNotifier<VisibleRangeDestination> visibleRangeDestination = ValueNotifier(VisibleRangeDestination.range);

/// The page the shared entry actually renders.
///
/// In the shared mode the entry hosts the pages and renders the stored choice.
/// With a separate entry the wallpaper page and the group editor have their own
/// bar entries and the range entry always renders the range page, so a stale
/// value (a gesture cold start, a value stored by an older build) can never take
/// over the range entry. A closed editor session also falls back to the range
/// page: the page is the session.
VisibleRangeDestination visibleRangeShellDestination({
  required GroupedWallpaperNavMode mode,
  required VisibleRangeDestination destination,
}) {
  if (mode != GroupedWallpaperNavMode.shared) return VisibleRangeDestination.range;
  if (destination == VisibleRangeDestination.editor && !visibleRangeEditorSession.active) return VisibleRangeDestination.range;
  return destination;
}

/// The page the shared entry renders.
class VisibleRangeShellPage extends StatelessWidget {
  /// Whether the wallpaper page opens on the group the wallpaper is playing.
  ///
  /// The bottom-bar entry keeps the user's browsing session; a page opened as the
  /// backdrop of the wallpaper view must describe the group that is on screen
  /// instead, exactly like the view it sits under.
  final bool selectCurrentWallpaperGroup;

  /// Whether the wallpaper page asks for the PIN at once.
  ///
  /// The notification's lock button deep-links the group page with this flag;
  /// routed through the shell, the shell has to pass it on instead of dropping
  /// the reason the user tapped.
  final bool promptUnlock;

  const new({super.key, this.selectCurrentWallpaperGroup = false, this.promptUnlock = false});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<GroupedWallpaperNavController, GroupedWallpaperNavMode>((v) => v.mode);
    return ValueListenableBuilder<VisibleRangeDestination>(
      valueListenable: visibleRangeDestination,
      builder: (context, destination, _) {
        final resolved = visibleRangeShellDestination(mode: mode, destination: destination);
        return switch (resolved) {
          VisibleRangeDestination.wallpaper => GroupedWallpaperPage(selectCurrent: selectCurrentWallpaperGroup, promptUnlock: promptUnlock),
          VisibleRangeDestination.editor => switch (visibleRangeEditorSession.groupId) {
            final groupId? => VisibleRangeGroupEditorPage(groupId: groupId),
            // The session closed between the destination write and this build:
            // the range page is always a valid surface.
            null => const VisibleRangePage(),
          },
          VisibleRangeDestination.range => const VisibleRangePage(),
        };
      },
    );
  }
}
