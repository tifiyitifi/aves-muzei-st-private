import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_group_editor_page.dart';
import 'package:aves/features/visible_range/view/visible_range_nav.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';

/// The bottom-bar destinations a surface should show.
///
/// The visible-range entry is appended first, then the fork pages that have an
/// open session are placed immediately left or right of it, so the peers stay
/// adjacent no matter where the user put the range entry. Nothing is written
/// into the user's `bottomNavigationActions`: the entries are derived at build
/// time.
///
/// - The wallpaper entry follows its **session** ([wallpaperSessionActive]); the
///   group editor follows [editorSessionActive]. Both appear when their page is
///   opened and stay until that page is closed.
/// - The two are ordered by [wallpaperOpenedAt] / [editorOpenedAt]: the page
///   opened first sits nearest the visible-range entry.
/// - A user who added `/wallpaper_groups` themselves owns the entry, so no second
///   one is derived ("pinned").
/// - [GroupedWallpaperNavMode.shared] keeps the single shell entry, which flips
///   between the pages instead of adding one.
/// - [include] is false while picking a photo, where a fork destination has no
///   meaning; the list is then returned untouched, like the range entry.
List<AvesNavItem> withForkNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool wallpaperSessionActive,
  required int wallpaperOpenedAt,
  required bool editorSessionActive,
  required int editorOpenedAt,
  bool include = true,
}) {
  if (!include) return configured;
  final items = [...withVisibleRangeDestination(configured)];
  // One entry hosts every page: nothing to place beside it.
  if (mode == GroupedWallpaperNavMode.shared) return items;

  final derived = <({int openedAt, AvesNavItem item})>[
    if (wallpaperSessionActive && items.every((item) => item.route != GroupedWallpaperPage.routeName))
      (openedAt: wallpaperOpenedAt, item: const AvesNavItem(route: GroupedWallpaperPage.routeName)),
    if (editorSessionActive && items.every((item) => item.route != VisibleRangeGroupEditorPage.routeName))
      (openedAt: editorOpenedAt, item: const AvesNavItem(route: VisibleRangeGroupEditorPage.routeName)),
  ]..sort((a, b) => a.openedAt.compareTo(b.openedAt));
  if (derived.isEmpty) return items;

  final rangeIndex = items.indexWhere((item) => item.route == VisibleRangePage.routeName);
  // The range entry is appended by the call above, so this is only a guard for
  // a future change there; the fork entries then go last.
  if (rangeIndex < 0) return [...items, for (final entry in derived) entry.item];

  // One block keeps the captured range index valid. Left: the first-opened sits
  // right against the range entry, so the block is reversed; right: it is the
  // first element of the block.
  final left = mode == GroupedWallpaperNavMode.separateLeft;
  final ordered = left ? derived.reversed : derived;
  items.insertAll(left ? rangeIndex : rangeIndex + 1, [for (final entry in ordered) entry.item]);
  return items;
}

/// The wallpaper-only view of [withForkNavDestinations], kept for callers that
/// do not know about the group editor.
List<AvesNavItem> withWallpaperNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool sessionActive,
  bool include = true,
}) {
  return withForkNavDestinations(
    configured,
    mode: mode,
    wallpaperSessionActive: sessionActive,
    wallpaperOpenedAt: 0,
    editorSessionActive: false,
    editorOpenedAt: 0,
    include: include,
  );
}

/// The destinations the bar adds on its own, on top of the user's own list.
///
/// The navigation editor lists `bottomNavigationActions` as editable buttons and
/// has to describe the bar the user actually sees, so the difference is shown
/// read-only instead of silently missing. Order is kept: it is where the bar
/// puts them.
///
/// The range entry is always derived and permanent. A fork entry is listed while
/// its session is open (and never in the shared mode, which derives none):
/// removing it there is the same close as the page's own action, so the editor
/// can offer it.
List<AvesNavItem> derivedNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool sessionActive,
  bool editorSessionActive = false,
}) {
  final effective = withForkNavDestinations(
    configured,
    mode: mode,
    wallpaperSessionActive: sessionActive,
    wallpaperOpenedAt: 0,
    editorSessionActive: editorSessionActive,
    editorOpenedAt: 0,
  );
  return effective.where((item) => !configured.contains(item)).toList();
}

/// Reads the process-wide sessions, so a bar or the navigation editor can build
/// the list without threading the state through every layer.
List<AvesNavItem> withCurrentForkNavDestinations(
  List<AvesNavItem> configured, {
  required GroupedWallpaperNavMode mode,
  required bool wallpaperSessionActive,
  required int wallpaperOpenedAt,
  bool include = true,
}) {
  return withForkNavDestinations(
    configured,
    mode: mode,
    wallpaperSessionActive: wallpaperSessionActive,
    wallpaperOpenedAt: wallpaperOpenedAt,
    editorSessionActive: visibleRangeEditorSession.active,
    editorOpenedAt: visibleRangeEditorSession.openedAt,
    include: include,
  );
}
