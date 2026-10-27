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

/// Evaluation of a visible range: two group orders, unrestricted bases, the
/// "restricted" rule, and the applied-target helpers.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  final image = MimeFilter.image;
  final video = MimeFilter.video;
  const favourite = FavouriteFilter.instance;
  CollectionFilter albumA() => PathFilter('/a');

  VisibleRange range({
    Set<CollectionFilter> base = const {},
    List<VisibleRangeRule> rules = const [],
    VisibleRangeOrder order = VisibleRangeOrder.intersectFirst,
  }) {
    return VisibleRange(
      id: 'r',
      scope: VisibleRangeScope.gallery,
      ownerId: VisibleRange.galleryOwnerId,
      baseFilters: base,
      rules: rules,
      order: order,
    );
  }

  VisibleRangeRule rule(String id, VisibleRangeRuleKind kind, Set<CollectionFilter> filters, {bool active = true, int position = 0}) {
    return VisibleRangeRule(id: id, rangeId: 'r', kind: kind, position: position, filters: filters, active: active);
  }

  group('evaluation', () {
    test('an empty range restricts nothing', () {
      expect(range().resolve(), isNull);
      expect(range().isRestricted, isFalse);
    });

    test('intersect-first combines base AND restrictions, then OR supplements', () {
      final resolved = range(
        base: {image},
        rules: [
          rule('r1', VisibleRangeRuleKind.restriction, {favourite}),
          rule('r2', VisibleRangeRuleKind.supplement, {video}),
        ],
      ).resolve();

      expect(resolved, isA<SetOrFilter>());
      final members = (resolved as SetOrFilter).innerFilters;
      expect(members, hasLength(2));
      expect(members.whereType<SetAndFilter>().single.innerFilters, {image, favourite});
      expect(members, contains(video));
    });

    test('union-first ORs supplements first, then ANDs restrictions', () {
      final resolved = range(
        base: {image},
        rules: [
          rule('r1', VisibleRangeRuleKind.restriction, {favourite}),
          rule('r2', VisibleRangeRuleKind.supplement, {video}),
        ],
        order: VisibleRangeOrder.unionFirst,
      ).resolve();

      expect(resolved, isA<SetAndFilter>());
      final members = (resolved as SetAndFilter).innerFilters;
      expect(members, contains(favourite));
      final union = members.whereType<SetOrFilter>().single;
      expect(union.innerFilters, {image, video});
    });

    test('an unrestricted base is a no-op in both orders', () {
      final restrictionOnly = [rule('r1', VisibleRangeRuleKind.restriction, {favourite})];
      expect(range(rules: restrictionOnly).resolve(), favourite);
      expect(range(rules: restrictionOnly, order: VisibleRangeOrder.unionFirst).resolve(), favourite);
    });

    test('a supplement alone never restricts browsing', () {
      final supplementOnly = [rule('s1', VisibleRangeRuleKind.supplement, {video})];
      // Intersect-first widens without narrowing; union-first is everything.
      expect(range(rules: supplementOnly).resolve(), video);
      expect(range(rules: supplementOnly, order: VisibleRangeOrder.unionFirst).resolve(), isNull);
      expect(range(rules: supplementOnly).isRestricted, isFalse);
    });

    test('inactive rules do not contribute', () {
      final inactive = [rule('r1', VisibleRangeRuleKind.restriction, {favourite}, active: false)];
      expect(range(base: {image}, rules: inactive).resolve(), image);
      expect(range(base: {image}, rules: inactive).isRestricted, isTrue);
    });

    test('restricted is decided by the base and restrictions only', () {
      expect(range(base: {albumA()}).isRestricted, isTrue);
      expect(range(base: {albumA()}).isRestricted, isTrue);
      expect(range(rules: [rule('r1', VisibleRangeRuleKind.restriction, {favourite})]).isRestricted, isTrue);
      expect(range(rules: [rule('s1', VisibleRangeRuleKind.supplement, {favourite})]).isRestricted, isFalse);
      expect(range().isUnrestricted, isTrue);
    });

    test('every rule filter is AND-ed inside its rule', () {
      final resolved = range(
        base: {image},
        rules: [rule('r1', VisibleRangeRuleKind.restriction, {favourite, albumA()})],
      ).resolve();
      expect((resolved as SetAndFilter).innerFilters, {image, favourite, albumA()});
    });

    test('the step queries mirror the evaluation order', () {
      final underTest = range(
        base: {image},
        rules: [
          rule('r1', VisibleRangeRuleKind.restriction, {favourite}),
          rule('r2', VisibleRangeRuleKind.supplement, {video}),
        ],
      );
      expect(underTest.resolvedBase, image);
      // Intersect-first: base AND restrictions, before supplements.
      expect((underTest.resolvedIntermediate! as SetAndFilter).innerFilters, {image, favourite});
      // Union-first: base OR supplements, before restrictions.
      expect((underTest.copyWith(order: VisibleRangeOrder.unionFirst).resolvedIntermediate! as SetOrFilter).innerFilters, {image, video});
    });

    test('an unrestricted base has no intermediate in union-first', () {
      final underTest = range(rules: [rule('s1', VisibleRangeRuleKind.supplement, {video})], order: VisibleRangeOrder.unionFirst);
      expect(underTest.resolvedBase, isNull);
      expect(underTest.resolvedIntermediate, isNull);
    });
  });

  group('fingerprint', () {
    test('is order independent and distinguishes different sets', () {
      expect(filterFingerprint({image, video}), filterFingerprint({video, image}));
      expect(filterFingerprint({image}), isNot(filterFingerprint({video})));
    });
  });

  group('applied targets', () {
    test('a rule target keeps its global id and kind', () {
      final usage = VisibleRangeRuleUsage.forRule(ruleId: 'rule.7', rangeId: 'gallery', kind: VisibleRangeRuleKind.supplement, usedAt: 3);
      expect(usage.id, 'rule.rule.7');
      expect(usage.targetId, 'rule.7');
      expect(usage.rangeId, 'gallery');
      expect(usage.kind, VisibleRangeCandidateKind.supplement);
      expect(usage.isBase, isFalse);
    });

    test('a base target is addressed by its range', () {
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
