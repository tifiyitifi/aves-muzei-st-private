import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A group stores its conditions once: home/lock are projections of the pool.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);
  VisibleRangeRule rule(String id, {int surfaces = WallpaperConditionSurfaces.all, VisibleRangeRuleKind kind = VisibleRangeRuleKind.restriction}) => VisibleRangeRule(
    id: id,
    rangeId: 'g.range',
    kind: kind,
    label: id,
    filters: {MimeFilter.image},
    surfaces: surfaces,
  );

  VisibleRange pool({int baseSurfaces = WallpaperConditionSurfaces.all, List<VisibleRangeRule> rules = const []}) => VisibleRange(
    id: 'g.range',
    scope: VisibleRangeScope.wallpaper,
    ownerId: 'g',
    baseName: 'Base',
    baseFilters: {PathFilter('/dcim')},
    baseSurfaces: baseSurfaces,
    rules: rules,
  );

  group('surface marks', () {
    test('one bit per surface', () {
      expect(WallpaperConditionSurfaces.of(WallpaperSurface.home), WallpaperConditionSurfaces.home);
      expect(WallpaperConditionSurfaces.of(WallpaperSurface.lock), WallpaperConditionSurfaces.lock);
      expect(WallpaperConditionSurfaces.withSurface(0, WallpaperSurface.lock, true), WallpaperConditionSurfaces.lock);
      expect(WallpaperConditionSurfaces.withSurface(WallpaperConditionSurfaces.all, WallpaperSurface.home, false), WallpaperConditionSurfaces.lock);
      expect(WallpaperConditionSurfaces.contains(WallpaperConditionSurfaces.all, WallpaperSurface.home), isTrue);
      expect(WallpaperConditionSurfaces.any(0), isFalse);
    });
  });

  group('projection', () {
    test('keeps the historical per-surface ids', () {
      final home = projectWallpaperGroupRange(pool(), groupId: 'g', surface: WallpaperSurface.home);
      final lock = projectWallpaperGroupRange(pool(), groupId: 'g', surface: WallpaperSurface.lock);
      expect(home.id, 'g.range');
      expect(home.ownerId, 'g');
      expect(lock.id, 'g.lock.range');
      expect(lock.ownerId, 'g.lock');
    });

    test('only marked conditions take part', () {
      final projected = projectWallpaperGroupRange(
        pool(
          rules: [
            rule('both'),
            rule('homeOnly', surfaces: WallpaperConditionSurfaces.home),
            rule('lockOnly', surfaces: WallpaperConditionSurfaces.lock),
            rule('unused', surfaces: 0),
          ],
        ),
        groupId: 'g',
        surface: WallpaperSurface.home,
      );
      expect(projected.rules.map((r) => r.id), ['both', 'homeOnly']);
      // Membership is the wallpaper page's switch, so a member is active.
      expect(projected.rules.every((r) => r.active), isTrue);
      expect(projected.resolve() != null, isTrue);
    });

    test('a surface that does not use the base is unrestricted by it', () {
      final lock = projectWallpaperGroupRange(
        pool(baseSurfaces: WallpaperConditionSurfaces.home),
        groupId: 'g',
        surface: WallpaperSurface.lock,
      );
      expect(lock.baseFilters, isEmpty);
      expect(lock.isBaseUnrestricted, isTrue);
    });

    test('the order and the lock belong to the pool', () {
      final source = pool().copyWith(order: VisibleRangeOrder.unionFirst, locked: true);
      final home = projectWallpaperGroupRange(source, groupId: 'g', surface: WallpaperSurface.home);
      expect(home.order, VisibleRangeOrder.unionFirst);
      expect(home.locked, isTrue);
    });
  });

  group('merge', () {
    test('a rule the projection keeps is updated in place and marked', () {
      final merged = mergeWallpaperGroupRange(
        pool(rules: [rule('a', surfaces: WallpaperConditionSurfaces.home)]),
        pool(
          rules: [rule('a', surfaces: WallpaperConditionSurfaces.all).copyWith(label: 'Renamed')],
        ),
        surface: WallpaperSurface.lock,
      );
      final stored = merged.ruleById('a')!;
      expect(stored.label, 'Renamed');
      expect(stored.surfaces, WallpaperConditionSurfaces.all);
    });

    test('a rule the projection drops only loses this surface', () {
      final merged = mergeWallpaperGroupRange(
        pool(rules: [rule('a')]),
        pool(rules: const []),
        surface: WallpaperSurface.lock,
      );
      expect(merged.ruleById('a')!.surfaces, WallpaperConditionSurfaces.home);
    });

    test('a new rule joins with this surface only', () {
      final merged = mergeWallpaperGroupRange(
        pool(rules: const []),
        pool(rules: [rule('new')]),
        surface: WallpaperSurface.lock,
      );
      expect(merged.ruleById('new')!.surfaces, WallpaperConditionSurfaces.lock);
      expect(merged.ruleById('new')!.active, isTrue);
    });

    test('a surface that does not use the base cannot erase it', () {
      final merged = mergeWallpaperGroupRange(
        pool(baseSurfaces: WallpaperConditionSurfaces.home),
        projectWallpaperGroupRange(
          pool(baseSurfaces: WallpaperConditionSurfaces.home),
          groupId: 'g',
          surface: WallpaperSurface.lock,
        ),
        surface: WallpaperSurface.lock,
      );
      expect(merged.baseFilters, {PathFilter('/dcim')});
      expect(merged.baseSurfaces, WallpaperConditionSurfaces.home);
    });

    test('using the base on a surface marks it', () {
      final merged = mergeWallpaperGroupRange(
        pool(baseSurfaces: WallpaperConditionSurfaces.home),
        pool().copyWith(baseFilters: {PathFilter('/pictures')}),
        surface: WallpaperSurface.lock,
      );
      expect(merged.baseSurfaces, WallpaperConditionSurfaces.all);
      expect(merged.baseFilters, {PathFilter('/pictures')});
    });
  });
}
