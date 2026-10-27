import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_sections.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The wallpaper group page is built from the group's own range only.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  VisibleRange range({
    Set<CollectionFilter> base = const {},
    bool baseActive = true,
    List<VisibleRangeRule> rules = const [],
  }) =>
      VisibleRange(
        id: 'wallpaper.group.dcim.range',
        scope: VisibleRangeScope.wallpaper,
        ownerId: 'wallpaper.group.dcim',
        baseName: '@wallpaperGroupDefaultDcim',
        baseFilters: base,
        baseActive: baseActive,
        rules: rules,
      );

  VisibleRangeRule rule(String id, VisibleRangeRuleKind kind, {bool active = true, Set<CollectionFilter> filters = const {}}) => VisibleRangeRule(
        id: id,
        rangeId: 'wallpaper.group.dcim.range',
        kind: kind,
        filters: filters.isEmpty ? {MimeFilter.image} : filters,
        active: active,
      );

  test('the base section starts with the no-filters control and never shows a gallery preset', () {
    final sections = buildWallpaperGroupSections(range: range(base: {PathFilter('/dcim')}));
    final base = sections.first;
    expect(base.kind, VisibleRangeCandidateKind.base);
    expect(base.candidates.map((candidate) => candidate.id), [wallpaperGroupNoFiltersId, VisibleRangeCandidate.customBaseId]);
    expect(base.candidates.first.placeholder, isTrue);
    expect(base.candidates.first.active, isFalse);
    expect(base.candidates.last.active, isTrue);
    expect(base.candidates.last.labelKey, 'wallpaperGroupDefaultDcim');
    // No gallery preset catalogue ever enters a group.
    expect(sections.expand((section) => section.candidates).where((candidate) => candidate.preset != null), isEmpty);
    expect(sections.expand((section) => section.candidates).where((candidate) => candidate.isBuiltinRule), isEmpty);
  });

  test('an empty group shows the no-filters control as active', () {
    final base = buildWallpaperGroupSections(range: range()).first;
    expect(base.candidates.single.id, wallpaperGroupNoFiltersId);
    expect(base.candidates.single.active, isTrue);
  });

  test('an empty rule section keeps one None slot; a populated one drops it', () {
    final empty = buildWallpaperGroupSections(range: range());
    final restrictions = empty.firstWhere((section) => section.kind == VisibleRangeCandidateKind.restriction);
    expect(restrictions.candidates, hasLength(1));
    expect(restrictions.candidates.single.placeholder, isTrue);
    expect(restrictions.candidates.single.labelKey, 'wallpaperGroupSectionNone');

    final populated = buildWallpaperGroupSections(range: range(rules: [rule('r1', VisibleRangeRuleKind.restriction)]));
    final populatedRestrictions = populated.firstWhere((section) => section.kind == VisibleRangeCandidateKind.restriction);
    expect(populatedRestrictions.candidates.map((candidate) => candidate.id), ['r1']);
  });

  test('switching the base off keeps its tile and makes no-filters active', () {
    final base = buildWallpaperGroupSections(range: range(base: {PathFilter('/dcim')}, baseActive: false)).first;
    expect(base.candidates.map((candidate) => candidate.id), [wallpaperGroupNoFiltersId, VisibleRangeCandidate.customBaseId]);
    expect(base.candidates.first.active, isTrue);
    expect(base.candidates.last.active, isFalse);
  });

  test('an active rule keeps the no-filters control inactive', () {
    final base = buildWallpaperGroupSections(
      range: range(base: {PathFilter('/dcim')}, baseActive: false, rules: [rule('r1', VisibleRangeRuleKind.restriction)]),
    ).first;
    expect(base.candidates.first.active, isFalse);
  });

  test('the active list only repeats real conditions', () {
    final active = buildWallpaperGroupActiveCandidates(
      range: range(
        base: {PathFilter('/dcim')},
        rules: [
          rule('r1', VisibleRangeRuleKind.restriction),
          rule('r2', VisibleRangeRuleKind.supplement, active: false),
        ],
      ),
    );
    expect(active.map((candidate) => candidate.id), [VisibleRangeCandidate.galleryId, VisibleRangeCandidate.customBaseId, 'r1']);
    expect(active.where((candidate) => candidate.placeholder), isEmpty);
  });
}
