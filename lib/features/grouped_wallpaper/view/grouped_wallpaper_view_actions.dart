import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_view_group_target.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';

/// Whether the "previous photo" control would do anything.
///
/// The engine walks the state's rewind stack, so this mirrors it exactly: no
/// photo on screen, a turned-off or unavailable wallpaper, recording off, or the
/// cursor already at the oldest record all grey the control instead of offering
/// a tap that does nothing.
bool groupedWallpaperCanGoPrevious(GroupedWallpaperState state) => state.canGoPrevious;

/// Whether the "next photo" control would change the frame.
///
/// A group with a single photo would re-bake the same frame, so the control is
/// greyed out instead of pretending to advance.
bool groupedWallpaperCanGoNext(GroupedWallpaperState state) => state.hasPhoto && state.count > 1;

/// Whether a "previous/next group" control would move the wallpaper.
///
/// It mirrors the bar: a locked group cannot leave, a turned-off wallpaper keeps
/// its last frame without following anything, the rotation needs another enabled
/// group, and group 0 is not part of the rotation (nothing is playing) so there
/// is nothing to step from.
bool groupedWallpaperCanStepGroup(GroupedWallpaperState state, {required bool locked}) =>
    !locked &&
    state.status != GroupedWallpaperStatus.disabled &&
    groupedWallpaperViewGroupTarget(
      groups: state.groups,
      currentId: state.groupId,
      delta: 1,
    ) !=
    null;

/// Where the view page's "Open wallpaper groups" action leads.
enum GroupedWallpaperViewGroupNavigation {
  /// Pop back to the group page already below the view.
  back,

  /// Push the group page over the view.
  pushGroupPage,
}

/// Decides how "Open wallpaper groups" reaches the group page.
///
/// The view has two entry points. Opened from the group page's menu, that page is
/// already below it, so going back is what the user means. Opened by a wallpaper
/// gesture or a notification, the view is the root route and the group page is a
/// detail pushed over it, so returning from the group page lands here again.
GroupedWallpaperViewGroupNavigation groupedWallpaperViewGroupNavigation({required bool groupPageBelow}) =>
    groupPageBelow ? GroupedWallpaperViewGroupNavigation.back : GroupedWallpaperViewGroupNavigation.pushGroupPage;

/// A gallery view the view page hands the photo on screen to.
///
/// [filters] is the scope the collection page opens, and [locateUri] is the entry
/// it reveals there. The reveal is the app's existing locate behaviour, so the
/// user lands on the photo they were just looking at instead of the list's top.
typedef GroupedWallpaperGalleryTarget = ({Set<CollectionFilter> filters, String? locateUri});

/// The album the photo on screen belongs to, for the「open in album」action.
///
/// This is the stored album, not the group's path condition: a condition covers
/// a folder tree, while the album is the one shelf the photo is filed under. Null
/// when the entry or its directory is unknown, because there is nothing to open.
GroupedWallpaperGalleryTarget? groupedWallpaperAlbumTarget(AvesEntry? entry, {required String? albumDisplayName}) {
  final album = entry?.directory;
  if (entry == null || album == null || album.isEmpty) return null;
  return (
    filters: {StoredAlbumFilter(album, albumDisplayName)},
    locateUri: entry.uri,
  );
}

/// The group's whole media set, on the surface the view is describing.
///
/// The range is the group's own, so this is what the wallpaper may draw from; the
/// collection page still joins the gallery's visible range, because browsing says
/// so everywhere else too.
GroupedWallpaperGalleryTarget groupedWallpaperWholeGroupTarget(VisibleRange? range, {required AvesEntry? entry}) => (
  filters: {wallpaperMediaSetFilter(range) ?? MimeFilter.image},
  locateUri: entry?.uri,
);
