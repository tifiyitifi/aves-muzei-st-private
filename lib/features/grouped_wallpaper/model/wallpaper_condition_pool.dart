import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';

/// How the wallpaper surfaces share one group's conditions.
///
/// A group owns one condition pool: its single `wallpaper` visible range row.
/// Every base and every rule is stored once, and each surface only records
/// whether it uses that condition. The pair of surfaces is therefore a bit mask
/// on the condition, not a second copy of it.
abstract final class WallpaperConditionSurfaces {
  static const int home = 1;
  static const int lock = 2;
  static const int all = home | lock;

  static int of(WallpaperSurface surface) => surface.isLock ? lock : home;

  static bool contains(int mask, WallpaperSurface surface) => mask & of(surface) != 0;

  /// [mask] with [surface]'s bit set or cleared.
  static int withSurface(int mask, WallpaperSurface surface, bool enabled) => enabled ? mask | of(surface) : mask & ~of(surface);

  /// Whether [mask] names at least one surface.
  static bool any(int mask) => mask & all != 0;
}

/// Projects one surface of a group's condition pool.
///
/// The result is the `VisibleRange` the engine, the browsing overlay and the
/// pin sheet have always consumed: only the conditions this surface marks, with
/// `active` set because membership is the wallpaper page's switch. The ids stay
/// the historical per-surface ids, so `state.json`, the decoy range id and the
/// history keep addressing the same ranges.
VisibleRange projectWallpaperGroupRange(VisibleRange pool, {required String groupId, required WallpaperSurface surface}) {
  final mask = WallpaperConditionSurfaces.of(surface);
  final usesBase = pool.baseSurfaces & mask != 0;
  return VisibleRange(
    id: surface.isLock ? wallpaperGroupLockRangeId(groupId) : wallpaperGroupRangeId(groupId),
    scope: VisibleRangeScope.wallpaper,
    ownerId: surface.isLock ? wallpaperGroupLockOwnerId(groupId) : groupId,
    baseName: usesBase ? pool.baseName : '',
    basePresetId: usesBase ? pool.basePresetId : '',
    baseFilters: usesBase ? pool.baseFilters : const {},
    baseActive: true,
    rules: [
      for (final rule in pool.rules)
        if (rule.surfaces & mask != 0) rule.copyWith(active: true),
    ],
    order: pool.order,
    locked: pool.locked,
    permissions: pool.permissions,
    createdAt: pool.createdAt,
    updatedAt: pool.updatedAt,
  );
}

/// Writes a surface's edited projection back into the pool.
///
/// The pool stays the single source of truth: a rule the surface kept is updated
/// in place (its shared label, kind and filters), a rule the surface dropped only
/// loses this surface's mark, and a rule the projection added joins the pool with
/// this surface's mark. Conditions the other surface marks are never removed by
/// editing this one, and a base the surface does not use leaves the shared base
/// values untouched.
VisibleRange mergeWallpaperGroupRange(VisibleRange pool, VisibleRange range, {required WallpaperSurface surface}) {
  final mask = WallpaperConditionSurfaces.of(surface);
  final usesBase = range.baseActive && range.baseFilters.isNotEmpty;
  final byId = {for (final rule in pool.rules) rule.id: rule};
  final incoming = {for (final rule in range.rules) rule.id: rule};
  final rules = <VisibleRangeRule>[
    for (final rule in pool.rules)
      switch (incoming[rule.id]) {
        final edited? => rule.copyWith(
          kind: edited.kind,
          position: edited.position,
          label: edited.label,
          description: edited.description,
          filters: edited.filters,
          active: true,
          surfaces: rule.surfaces | mask,
        ),
        // The surface stopped using it: keep the condition for the other one.
        null => rule.surfaces & mask != 0 ? rule.copyWith(active: true, surfaces: rule.surfaces & ~mask) : rule,
      },
    // Conditions the projection created (a pin, a restored backup) join the pool
    // with this surface's mark only.
    for (final rule in range.rules)
      if (!byId.containsKey(rule.id)) rule.copyWith(active: true, surfaces: mask),
  ];
  return pool.copyWith(
    baseName: usesBase ? range.baseName : pool.baseName,
    basePresetId: usesBase ? range.basePresetId : pool.basePresetId,
    baseFilters: usesBase ? range.baseFilters : pool.baseFilters,
    baseActive: true,
    baseSurfaces: WallpaperConditionSurfaces.withSurface(pool.baseSurfaces, surface, usesBase),
    rules: rules,
    // The evaluation order belongs to the pool; the projection carries the
    // same value, so taking it back is a no-op unless an external writer
    // changed it.
    order: range.order,
    updatedAt: range.updatedAt,
  );
}
