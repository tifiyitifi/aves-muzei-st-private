import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_page_sections.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The gallery page lists the mutually exclusive groups, then the scope-wide
/// outside pool, then the current result. A group's own conditions live in its
/// editor, never in this list.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  final image = MimeFilter.image;
  const favourite = FavouriteFilter.instance;
  PathFilter album() => PathFilter('/a');

  VisibleRange group(String id, {String name = '', int position = 0, List<VisibleRangeRule> rules = const []}) => VisibleRange(
    id: id,
    scope: VisibleRangeScope.gallery,
    ownerId: id,
    name: name,
    position: position,
    rules: rules,
  );

  VisibleRangeRule rule(String rangeId, VisibleRangeRuleKind kind, {Set<CollectionFilter>? filters}) => VisibleRangeRule(
    id: 'rule.$rangeId.${kind.name}',
    rangeId: rangeId,
    kind: kind,
    filters: filters ?? {favourite},
  );

  VisibleRange outside({List<VisibleRangeRule> rules = const []}) => VisibleRange(
    id: VisibleRange.galleryOutsideId,
    scope: VisibleRangeScope.gallery,
    kind: VisibleRangeGroupKind.outside,
    ownerId: VisibleRange.galleryOutsideId,
    rules: rules,
  );

  test('the groups section starts with the sentinel and ends with the add tile', () {
    final sections = buildVisibleRangePageSections(
      groups: [group(VisibleRange.galleryRangeId), group('g1', name: 'Trips', position: 1)],
      currentGroupId: VisibleRange.galleryRangeId,
      outside: outside(),
    );
    final groups = sections.first;
    expect(groups.kind, VisibleRangePageSectionKind.groups);
    expect(groups.candidates.first.groupId, VisibleRange.galleryRangeId);
    expect(groups.candidates.first.labelKey, 'visibleRangeUnrestricted');
    expect(groups.candidates.first.active, isTrue);
    expect(groups.candidates[1].groupId, 'g1');
    expect(groups.candidates[1].active, isFalse);
    expect(groups.candidates.last.isGroupAdd, isTrue);
  });

  test('a group tile carries the group joined with the outside pool', () {
    final sections = buildVisibleRangePageSections(
      groups: [
        group(VisibleRange.galleryRangeId),
        group('g1', name: 'Trips', position: 1, rules: [rule('g1', VisibleRangeRuleKind.source, filters: {album()})]),
      ],
      currentGroupId: 'g1',
      outside: outside(rules: [rule(VisibleRange.galleryOutsideId, VisibleRangeRuleKind.restriction)]),
    );
    final trip = sections.first.candidates.firstWhere((candidate) => candidate.groupId == 'g1');
    expect(trip.filters.single, isA<SetAndFilter>());
    expect((trip.filters.single as SetAndFilter).innerFilters, {album(), favourite});
    expect(trip.labelKey, isEmpty);
    expect(trip.label, 'Trips');
    expect(trip.isApplicable, isFalse, reason: 'a group tile switches browsing, it is not a condition');
  });

  test('the outside sections are always present and read restrictions first', () {
    final sections = buildVisibleRangePageSections(
      groups: [group(VisibleRange.galleryRangeId)],
      currentGroupId: VisibleRange.galleryRangeId,
      outside: outside(
        rules: [
          rule(VisibleRange.galleryOutsideId, VisibleRangeRuleKind.supplement, filters: {image}),
          rule(VisibleRange.galleryOutsideId, VisibleRangeRuleKind.restriction),
        ],
      ),
    );
    expect(sections.map((section) => section.kind), [
      VisibleRangePageSectionKind.groups,
      VisibleRangePageSectionKind.outsideRestriction,
      VisibleRangePageSectionKind.outsideSupplement,
    ]);
    expect(sections[1].candidates.single.rule!.kind, VisibleRangeRuleKind.restriction);
    expect(sections[2].candidates.single.rule!.kind, VisibleRangeRuleKind.supplement);
  });
}
