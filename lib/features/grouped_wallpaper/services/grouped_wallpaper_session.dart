import 'dart:async';

import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';

/// Ends the wallpaper page session: the bar loses its entry and the group's
/// browsing scope stops constraining the library.
///
/// This is the one close path, shared by the page's "Close wallpaper page"
/// action and by removing the entry in the navigation settings, so the two can
/// never disagree about what closing means. Leaving the page (another
/// destination, the back gesture) is not a close and must not call this.
///
/// [owner] is the scope token of the page doing the closing. Passing it keeps a
/// page that was already replaced from clearing the newer page's scope; callers
/// with no page mounted (the navigation settings) omit it, which drops the
/// scope unconditionally.
void closeGroupedWallpaperSession({Object? owner}) {
  groupedWallpaperNavController.closeSession();
  if (owner != null) {
    unawaited(VisibleRangeGate.releaseWallpaperScope(owner));
  } else {
    VisibleRangeGate.clearWallpaperScope();
  }
}
