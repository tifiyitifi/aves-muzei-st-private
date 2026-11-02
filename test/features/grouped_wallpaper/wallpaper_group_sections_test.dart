import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_sections.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The wallpaper group page is built from the group's own condition pool.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  VisibleRange pool({
    Set<CollectionFilter> base = const {},
    int baseSurfaces = WallpaperConditionSurfaces.all,
    List<VisibleRangeRule> rules = const [],
  }) => VisibleRange(
    id: 'wallpaper.group.dcim.range',
    scope: VisibleRangeScope.wallpaper,
    ownerId: 'wallpaper.group.dcim',
    baseName: '@wallpaperGroupDefaultDcim',
    baseFilters: base,
    baseSurfaces: base.isEmpty ? 0 : baseSurfaces,
    rules: rules,
  );

  VisibleRangeRule rule(
    String id,
    VisibleRangeRuleKind kind, {
    int surfaces = WallpaperConditionSurfaces.all,
    Set<CollectionFilter> filters = const {},
  }) => VisibleRangeRule(
    id: id,
    rangeId: 'wallpaper.group.dcim.range',
    kind: kind,
    filters: filters.isEmpty ? {MimeFilter.image} : filters,
    surfaces: surfaces,
  );

  test('the base section starts with All images and never shows a gallery preset', () {
    final sections = buildWallpaperGroupPoolSections(
      pool: pool(base: {PathFilter('/dcim')}),
      active: WallpaperSurface.home,
    );
    final base = sections.first;
    expect(base.kind, VisibleRangeCandidateKind.base);
    expect(base.candidates.map((candidate) => candidate.id), [VisibleRangeCandidate.unrestrictedId, VisibleRangeCandidate.customBaseId]);
    final allImages = base.candidates.first;
    expect(allImages.placeholder, isFalse);
    expect(allImages.labelKey, 'wallpaperGroupAllImages');
    expect(allImages.active, isFalse);
    // A wallpaper only ever shows images, so the tile previews the image set:
    // that is what makes its cover and count agree with the group cards.
    expect(allImages.filters, {MimeFilter.image});
    expect(allImages.statsKey, filterFingerprint({MimeFilter.image}));
    expect(allImages.isApplicable, isFalse);
    // The base tile carries the surfaces that use it.
    expect(base.candidates.last.active, isTrue);
    expect(base.candidates.last.surfaces, WallpaperConditionSurfaces.all);
    expect(base.candidates.last.labelKey, 'wallpaperGroupDefaultDcim');
    // No gallery preset catalogue ever enters a group.
    expect(sections.expand((section) => section.candidates).where((candidate) => candidate.preset != null), isEmpty);
    expect(sections.expand((section) => section.candidates).where((candidate) => candidate.isBuiltinRule), isEmpty);
  });

  test('an empty group shows All images as active', () {
    final base = buildWallpaperGroupPoolSections(pool: pool(), active: WallpaperSurface.home).first;
    expect(base.candidates.single.id, VisibleRangeCandidate.unrestrictedId);
    expect(base.candidates.single.active, isTrue);
  });

  test('an empty rule section keeps one None slot; a populated one drops it', () {
    final empty = buildWallpaperGroupPoolSections(pool: pool(), active: WallpaperSurface.home);
    final restrictions = empty.firstWhere((section) => section.kind == VisibleRangeCandidateKind.restriction);
    expect(restrictions.candidates, hasLength(1));
    expect(restrictions.candidates.single.placeholder, isTrue);
    expect(restrictions.candidates.single.labelKey, 'wallpaperGroupSectionNone');

    final populated = buildWallpaperGroupPoolSections(
      pool: pool(rules: [rule('r1', VisibleRangeRuleKind.restriction)]),
      active: WallpaperSurface.home,
    );
    final populatedRestrictions = populated.firstWhere((section) => section.kind == VisibleRangeCandidateKind.restriction);
    expect(populatedRestrictions.candidates.map((candidate) => candidate.id), ['r1']);
  });

  test('a condition stored once is listed once and carries both surface marks', () {
    final sections = buildWallpaperGroupPoolSections(
      pool: pool(rules: [rule('r1', VisibleRangeRuleKind.restriction)]),
      active: WallpaperSurface.home,
    );
    final candidates = sections.expand((section) => section.candidates).where((candidate) => candidate.rule != null).toList();
    expect(candidates, hasLength(1));
    expect(candidates.single.id, 'r1');
    expect(candidates.single.surfaces, WallpaperConditionSurfaces.all);
    expect(candidates.single.active, isTrue);

    // The same condition, read from the other surface: still one row, active too.
    final lock = buildWallpaperGroupPoolSections(
      pool: pool(rules: [rule('r1', VisibleRangeRuleKind.restriction)]),
      active: WallpaperSurface.lock,
    ).expand((section) => section.candidates).where((candidate) => candidate.rule != null).single;
    expect(lock.id, 'r1');
    expect(lock.active, isTrue);
  });

  test('the edited surface reads the mark as its switch', () {
    final sections = buildWallpaperGroupPoolSections(
      pool: pool(rules: [rule('r1', VisibleRangeRuleKind.restriction, surfaces: WallpaperConditionSurfaces.lock)]),
      active: WallpaperSurface.home,
    );
    final candidate = sections.expand((section) => section.candidates).firstWhere((candidate) => candidate.rule != null);
    // Home does not use it, so its own state is off, while the lock mark is kept.
    expect(candidate.active, isFalse);
    expect(candidate.surfaces, WallpaperConditionSurfaces.lock);
  });

  test('a surface summary lists what that surface applies', () {
    final range = VisibleRange(
      id: 'wallpaper.group.dcim.lock.range',
      scope: VisibleRangeScope.wallpaper,
      ownerId: 'wallpaper.group.dcim.lock',
      baseName: 'DCIM',
      baseFilters: {PathFilter('/dcim')},
      rules: [
        rule('r1', VisibleRangeRuleKind.restriction),
        rule('r2', VisibleRangeRuleKind.supplement, surfaces: 0).copyWith(active: false),
      ],
    );
    final candidates = buildWallpaperGroupSurfaceCandidates(range: range);
    expect(candidates.map((candidate) => candidate.id), [VisibleRangeCandidate.customBaseId, 'r1']);
    expect(candidates.where((candidate) => candidate.placeholder), isEmpty);
  });

  test('an empty surface summary keeps one None slot', () {
    const range = VisibleRange(
      id: 'wallpaper.group.dcim.lock.range',
      scope: VisibleRangeScope.wallpaper,
      ownerId: 'wallpaper.group.dcim.lock',
    );
    final candidates = buildWallpaperGroupSurfaceCandidates(range: range);
    expect(candidates, hasLength(1));
    expect(candidates.single.placeholder, isTrue);
  });
}
