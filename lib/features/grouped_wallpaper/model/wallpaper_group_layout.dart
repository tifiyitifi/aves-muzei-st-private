import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:collection/collection.dart';

/// Re-applies every invariant the store and the page rely on:
///
/// - the enabled groups form the first segment (`1..m`), the disabled ones the
///   second (`m+1..n`), preserving the order inside each segment;
/// - numbers are contiguous `1..n` following that order;
/// - at most one group is `current`, and it must be enabled.
///
/// Normalizing is idempotent, so it is safe to run after every mutation and on
/// load. Running it on load also repairs a database edited by an older build or
/// left inconsistent by a crash.
List<WallpaperGroup> normalizeWallpaperGroups(Iterable<WallpaperGroup> groups) {
  final list = groups.toList();
  final ordered = [
    for (final group in list)
      if (group.enabled) group,
    for (final group in list)
      if (!group.enabled) group,
  ];
  final currentId = ordered.firstWhereOrNull((group) => group.current && group.enabled)?.id;
  return [
    for (var i = 0; i < ordered.length; i++)
      ordered[i].copyWith(
        number: i + 1,
        current: ordered[i].id == currentId,
      ),
  ];
}

/// Moves a group by [delta] slots inside its own segment.
///
/// Dragging never crosses the enabled/disabled boundary: that boundary has its
/// own action (the enable switch), so a drag can never silently disable a group.
List<WallpaperGroup> moveWallpaperGroup(List<WallpaperGroup> groups, String id, int delta) {
  final normalized = normalizeWallpaperGroups(groups);
  final index = normalized.indexWhere((group) => group.id == id);
  if (index < 0 || delta == 0) return normalized;

  final enabledCount = normalized.where((group) => group.enabled).length;
  final isEnabled = normalized[index].enabled;
  final start = isEnabled ? 0 : enabledCount;
  final end = (isEnabled ? enabledCount : normalized.length) - 1;
  final target = (index + delta).clamp(start, end);
  if (target == index) return normalized;

  final list = [...normalized];
  final group = list.removeAt(index);
  list.insert(target, group);
  return normalizeWallpaperGroups(list);
}

/// Turns a group on or off, following the segment rule from the product spec:
///
/// - enabling joins the **end** of the enabled segment;
/// - disabling joins the **start** of the disabled segment;
/// - disabling the current group clears `current`, so the wallpaper falls back
///   to group 0 instead of pointing at a group that is no longer rotated.
List<WallpaperGroup> setWallpaperGroupEnabled(List<WallpaperGroup> groups, String id, bool enabled) {
  final normalized = normalizeWallpaperGroups(groups);
  final index = normalized.indexWhere((group) => group.id == id);
  if (index < 0 || normalized[index].enabled == enabled) return normalized;

  final list = [...normalized];
  final group = list.removeAt(index);
  final enabledCount = list.where((candidate) => candidate.enabled).length;
  list.insert(
    enabledCount,
    group.copyWith(enabled: enabled, current: enabled && group.current),
  );
  return normalizeWallpaperGroups(list);
}

/// Id of the current group, or null when group 0 is current.
String? currentWallpaperGroupId(Iterable<WallpaperGroup> groups) => groups.firstWhereOrNull((group) => group.current && group.enabled)?.id;

/// The groups the notification rotation cycles, in display order.
List<WallpaperGroup> enabledWallpaperGroups(Iterable<WallpaperGroup> groups) => [
      for (final group in normalizeWallpaperGroups(groups))
        if (group.enabled) group,
    ];
