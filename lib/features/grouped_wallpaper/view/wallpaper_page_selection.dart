import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/filters/filters.dart';

/// The wallpaper page's two independent multi-selection scopes.
///
/// The group cards choose which range is edited, while the condition tiles edit
/// that range; they share one scroll view and one `Selection`, so a range gesture
/// could otherwise cross from a condition into the group cards above it and mix
/// two different actions (apply to a media set, delete groups, ...).
enum WallpaperPageSelectionScope {
  /// No decision yet: the selection is empty, or (invalidly) mixed.
  none,

  /// Group cards only: group management.
  groups,

  /// Condition tiles only: the range's base and rules.
  conditions,
}

/// The scope [filter] belongs to, or [WallpaperPageSelectionScope.none].
WallpaperPageSelectionScope wallpaperPageItemScope(CollectionFilter filter) {
  if (filter is WallpaperGroupFilter) return WallpaperPageSelectionScope.groups;
  if (filter is VisibleRangeCandidateFilter) return WallpaperPageSelectionScope.conditions;
  return WallpaperPageSelectionScope.none;
}

/// The scope a selection covers, or [WallpaperPageSelectionScope.none] when it
/// is empty or holds items of both scopes.
WallpaperPageSelectionScope wallpaperPageSelectionScope(Iterable<CollectionFilter> filters) {
  var groups = false;
  var conditions = false;
  for (final filter in filters) {
    switch (wallpaperPageItemScope(filter)) {
      case WallpaperPageSelectionScope.groups:
        groups = true;
      case WallpaperPageSelectionScope.conditions:
        conditions = true;
      case WallpaperPageSelectionScope.none:
        break;
    }
  }
  if (groups == conditions) return WallpaperPageSelectionScope.none;
  return groups ? WallpaperPageSelectionScope.groups : WallpaperPageSelectionScope.conditions;
}

/// Whether an item of the given kind may join a selection scoped to [scope].
///
/// [WallpaperPageSelectionScope.none] accepts both, which is what lets either
/// grid start a selection.
bool wallpaperPageItemInScope(WallpaperPageSelectionScope scope, {required bool isGroup}) => switch (scope) {
  WallpaperPageSelectionScope.none => true,
  WallpaperPageSelectionScope.groups => isGroup,
  WallpaperPageSelectionScope.conditions => !isGroup,
};
