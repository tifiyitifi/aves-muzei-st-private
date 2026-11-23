import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Evaluation of a visibility group: the three roles, the two orders, the
/// scope-wide outside layer and the "restricted" rule.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  final image = MimeFilter.image;
  final video = MimeFilter.video;
  const favourite = FavouriteFilter.instance;
  CollectionFilter albumA() => PathFilter('/a');

  VisibleRangeRule rule(String id, VisibleRangeRuleKind kind, Set<CollectionFilter> filters, {bool active = true, int position = 0}) {
    return VisibleRangeRule(id: id, rangeId: 'r', kind: kind, position: position, filters: filters, active: active);
  }

  VisibleRange range({
    Set<CollectionFilter> sources = const {},
    bool sourceActive = true,
    Set<CollectionFilter> restrictions = const {},
    List<VisibleRangeRule> rules = const [],
    VisibleRangeOrder order = VisibleRangeOrder.intersectFirst,
  }) {
    final sourceRules = sources.isEmpty ? const <VisibleRangeRule>[] : [rule('source', VisibleRangeRuleKind.source, sources, active: sourceActive)];
    final restrictionRules = restrictions.isEmpty ? const <VisibleRangeRule>[] : [rule('restriction', VisibleRangeRuleKind.restriction, restrictions)];
    return VisibleRange(
      id: 'r',
      scope: VisibleRangeScope.gallery,
      ownerId: VisibleRange.galleryOwnerId,
      rules: [...sourceRules, ...restrictionRules, ...rules],
      order: order,
    );
  }

  VisibleRange outside({List<VisibleRangeRule> rules = const []}) => VisibleRange(
    id: VisibleRange.galleryOutsideId,
    scope: VisibleRangeScope.gallery,
    kind: VisibleRangeGroupKind.outside,
    ownerId: VisibleRange.galleryOutsideId,
    rules: rules,
  );

  group('evaluation', () {
    test('an empty range restricts nothing', () {
      expect(range().resolve(), isNull);
      expect(range().isRestricted(), isFalse);
    });

    test('a switched-off source does not restrict and keeps its filters', () {
      final off = range(sources: {image}, sourceActive: false);
      expect(off.rulesOf(VisibleRangeRuleKind.source).single.filters, {image});
      expect(off.resolve(), isNull);
      expect(off.isRestricted(), isFalse);
      expect(off.isUnrestricted(), isTrue);
      final withRestriction = range(sources: {image}, sourceActive: false, restrictions: {favourite});
      expect(withRestriction.resolve(), favourite);
      expect(withRestriction.isRestricted(), isTrue);
    });

    test('intersect-first combines sources AND restrictions, then OR supplements', () {
      final resolved = range(
        sources: {image},
        restrictions: {favourite},
        rules: [rule('s1', VisibleRangeRuleKind.supplement, {video})],
      ).resolve();

      expect(resolved, isA<SetOrFilter>());
      final members = (resolved as SetOrFilter).innerFilters;
      expect(members, hasLength(2));
      expect(members.whereType<SetAndFilter>().single.innerFilters, {image, favourite});
      expect(members, contains(video));
    });

    test('union-first ORs supplements first, then ANDs restrictions', () {
      final resolved = range(
        sources: {image},
        restrictions: {favourite},
        rules: [rule('s1', VisibleRangeRuleKind.supplement, {video})],
        order: VisibleRangeOrder.unionFirst,
      ).resolve();

      expect(resolved, isA<SetAndFilter>());
      final members = (resolved as SetAndFilter).innerFilters;
      expect(members, contains(favourite));
      final union = members.whereType<SetOrFilter>().single;
      expect(union.innerFilters, {image, video});
    });

    test('an unrestricted source is a no-op in both orders', () {
      final restrictionOnly = {favourite};
      expect(range(restrictions: restrictionOnly).resolve(), favourite);
      expect(range(restrictions: restrictionOnly, order: VisibleRangeOrder.unionFirst).resolve(), favourite);
    });

    test('a supplement alone never restricts browsing', () {
      final supplementOnly = [rule('s1', VisibleRangeRuleKind.supplement, {video})];
      // A supplement can only add back; with nothing to add to, the group is
      // still everything, in both orders.
      expect(range(rules: supplementOnly).resolve(), isNull);
      expect(range(rules: supplementOnly, order: VisibleRangeOrder.unionFirst).resolve(), isNull);
      expect(range(rules: supplementOnly).isRestricted(), isFalse);
    });

    test('inactive rules do not contribute', () {
      final inactive = [rule('r1', VisibleRangeRuleKind.restriction, {favourite}, active: false)];
      expect(range(sources: {image}, rules: inactive).resolve(), image);
      expect(range(sources: {image}, rules: inactive).isRestricted(), isTrue);
    });

    test('several sources are a union, not a narrower conjunction', () {
      final resolved = range(
        sources: {albumA()},
        rules: [
          rule('source.2', VisibleRangeRuleKind.source, {image}, position: 1),
        ],
      ).resolve();
      expect(resolved, isA<SetOrFilter>());
      expect((resolved as SetOrFilter).innerFilters, {albumA(), image});
    });

    test('restricted is decided by the sources and restrictions only', () {
      expect(range(sources: {albumA()}).isRestricted(), isTrue);
      expect(range(restrictions: {favourite}).isRestricted(), isTrue);
      expect(range(rules: [rule('s1', VisibleRangeRuleKind.supplement, {favourite})]).isRestricted(), isFalse);
      expect(range().isUnrestricted(), isTrue);
    });

    test('every rule filter is AND-ed inside its rule', () {
      final resolved = range(
        sources: {image},
        restrictions: {favourite, albumA()},
      ).resolve();
      expect((resolved as SetAndFilter).innerFilters, {image, favourite, albumA()});
    });

    test('parking the sources keeps their filters and stops restricting', () {
      final parked = range(sources: {image}, restrictions: {favourite}).parkSources();
      final source = parked.rulesOf(VisibleRangeRuleKind.source).single;
      expect(source.active, isFalse);
      expect(source.filters, {image});
      // Only the sources are parked; the restriction still narrows.
      expect(parked.resolve(), favourite);
    });
  });

  group('outside layer', () {
    test('applies last: group AND outside restrictions, then outside supplements', () {
      final resolved = range(sources: {albumA()}, restrictions: {image}).resolve(
        outside: outside(rules: [
          rule('or1', VisibleRangeRuleKind.restriction, {favourite}),
          rule('os1', VisibleRangeRuleKind.supplement, {video}),
        ]),
      );
      // (A AND image AND favourite) OR video
      expect(resolved, isA<SetOrFilter>());
      final members = (resolved as SetOrFilter).innerFilters;
      expect(members, contains(video));
      expect(members.whereType<SetAndFilter>().single.innerFilters, {albumA(), image, favourite});
    });

    test('an outside supplement cannot restrict an otherwise unrestricted group', () {
      expect(range().resolve(outside: outside(rules: [rule('os1', VisibleRangeRuleKind.supplement, {video})])), isNull);
    });

    test('an outside restriction narrows even when the group has no source', () {
      expect(range().resolve(outside: outside(rules: [rule('or1', VisibleRangeRuleKind.restriction, {favourite})])), favourite);
      expect(range().isRestricted(outside: outside(rules: [rule('or1', VisibleRangeRuleKind.restriction, {favourite})])), isTrue);
    });

    test('the outside pool has no source role', () {
      expect(VisibleRangeRuleKind.source.isOutsideAllowed, isFalse);
      expect(VisibleRangeRuleKind.restriction.isOutsideAllowed, isTrue);
      expect(VisibleRangeRuleKind.supplement.isOutsideAllowed, isTrue);
    });
  });

  group('fingerprint', () {
    test('is order independent and distinguishes different sets', () {
      expect(filterFingerprint({image, video}), filterFingerprint({video, image}));
      expect(filterFingerprint({image}), isNot(filterFingerprint({video})));
    });
  });

  group('applied targets', () {
    test('a source rule target maps to the source section', () {
      final usage = VisibleRangeRuleUsage.forRule(ruleId: 'rule.7', rangeId: 'gallery', kind: VisibleRangeRuleKind.source, usedAt: 3);
      expect(usage.id, 'rule.rule.7');
      expect(usage.kind, VisibleRangeCandidateKind.base);
      expect(usage.isBase, isFalse);
    });

    test('a legacy base target is addressed by its range', () {
      final usage = VisibleRangeRuleUsage.forBase(rangeId: 'group.1.range', usedAt: 4);
      expect(usage.id, 'base.group.1.range');
      expect(usage.targetId, isEmpty);
      expect(usage.kind, VisibleRangeCandidateKind.base);
      expect(usage.isBase, isTrue);
    });

    test('the same target maps to one stable usage id', () {
      expect(baseUsageId('gallery'), baseUsageId('gallery'));
      expect(ruleUsageId('a'), isNot(ruleUsageId('b')));
    });
  });
}
