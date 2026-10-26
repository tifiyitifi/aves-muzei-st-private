import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page's three sections and the tile values behind them.
void main() {
  final image = MimeFilter.image;
  final video = MimeFilter.video;

  VisibleRangePreset preset(String id, Set<CollectionFilter> filters, {String? name}) =>
      VisibleRangePreset(id: id, name: name ?? id, filters: filters, builtin: name == null);

  VisibleRangeRule rule(String id, VisibleRangeRuleKind kind, Set<CollectionFilter> filters, {bool active = false, int position = 0, String label = ''}) =>
      VisibleRangeRule(id: id, rangeId: 'gallery', kind: kind, position: position, label: label, filters: filters, active: active);

  test('the base section starts with the unrestricted tile', () {
    final sections = buildVisibleRangeSections(range: VisibleRange.emptyGallery(), presets: const []);
    final base = sections.firstWhere((section) => section.kind == VisibleRangeCandidateKind.base);
    expect(base.candidates.single.isUnrestricted, isTrue);
    expect(base.candidates.single.active, isTrue);
  });

  test('unrestricted becomes an unselected option when a base is chosen', () {
    final range = VisibleRange.emptyGallery().copyWith(basePresetId: 'builtin.image', baseFilters: {image});
    final sections = buildVisibleRangeSections(range: range, presets: [preset('builtin.image', {image})]);
    final base = sections.firstWhere((section) => section.kind == VisibleRangeCandidateKind.base).candidates;
    expect(base.first.isUnrestricted, isTrue);
    expect(base.first.active, isFalse);
    expect(base.last.active, isTrue);
    expect(base.last.preset?.id, 'builtin.image');
  });

  test('a base whose preset was deleted keeps a selected custom tile', () {
    final range = VisibleRange.emptyGallery().copyWith(baseName: 'Saved', baseFilters: {image});
    final sections = buildVisibleRangeSections(range: range, presets: const []);
    final base = sections.firstWhere((section) => section.kind == VisibleRangeCandidateKind.base).candidates;
    final custom = base.firstWhere((candidate) => candidate.id == VisibleRangeCandidate.customBaseId);
    expect(custom.active, isTrue);
    expect(custom.label, 'Saved');
    expect(custom.filters, {image});
  });

  test('rules are grouped by kind and defaults come first', () {
    final range = VisibleRange.emptyGallery().copyWith(
      rules: [
        rule('user.1', VisibleRangeRuleKind.restriction, {image}, position: 0, active: true),
        rule('builtin.rule.builtin.restriction.portrait', VisibleRangeRuleKind.restriction, {image}, position: 5, label: '@visibleRangePresetPortrait'),
        rule('builtin.rule.builtin.supplement.video', VisibleRangeRuleKind.supplement, {video}, position: 0),
      ],
    );
    final sections = buildVisibleRangeSections(range: range, presets: const []);
    final restrictions = sections.firstWhere((section) => section.kind == VisibleRangeCandidateKind.restriction).candidates;
    final supplements = sections.firstWhere((section) => section.kind == VisibleRangeCandidateKind.supplement).candidates;
    expect(restrictions.map((candidate) => candidate.id), [
      'builtin.rule.builtin.restriction.portrait',
      'user.1',
    ]);
    expect(supplements.map((candidate) => candidate.id), ['builtin.rule.builtin.supplement.video']);
    expect(supplements.single.active, isFalse);
  });

  test('a built-in label is a key and a rename is plain text', () {
    final builtin = VisibleRangeCandidate.fromRule(rule('builtin.rule.x', VisibleRangeRuleKind.restriction, {image}, label: '@visibleRangePresetPortrait'));
    expect(builtin.labelKey, 'visibleRangePresetPortrait');
    expect(builtin.label, isEmpty);

    final renamed = VisibleRangeCandidate.fromRule(rule('builtin.rule.x', VisibleRangeRuleKind.restriction, {image}, label: 'My rule'));
    expect(renamed.labelKey, isEmpty);
    expect(renamed.label, 'My rule');
  });

  test('candidates with the same filters share a stats key', () {
    final a = VisibleRangeCandidate.fromRule(rule('a', VisibleRangeRuleKind.restriction, {image}));
    final b = VisibleRangeCandidate.fromRule(rule('b', VisibleRangeRuleKind.supplement, {image}));
    expect(a.statsKey, b.statsKey);
    expect(a.id, isNot(b.id));
  });

  test('a preset name is localized only for built-ins', () {
    final builtin = VisibleRangeCandidate.fromPreset(preset('builtin.image', {image}), active: false);
    expect(builtin.labelKey, 'builtin.image');
    expect(builtin.label, isEmpty);

    final user = VisibleRangeCandidate.fromPreset(preset('user.1', {image}, name: 'Mine'), active: false);
    expect(user.labelKey, isEmpty);
    expect(user.label, 'Mine');
  });

  test('the unrestricted tile is const and never carries filters', () {
    expect(VisibleRangeCandidate.unrestricted.filters, isEmpty);
    expect(VisibleRangeCandidate.unrestricted.active, isTrue);
  });

  test('the active section repeats the result, the base and the enabled rules', () {
    final range = VisibleRange.emptyGallery().copyWith(
      basePresetId: 'builtin.image',
      baseName: 'image',
      baseFilters: {image},
      rules: [
        rule('r1', VisibleRangeRuleKind.restriction, {image}, position: 0, active: true),
        rule('s1', VisibleRangeRuleKind.supplement, {video}, position: 0, active: true),
        rule('off', VisibleRangeRuleKind.restriction, {video}, position: 1),
      ],
    );
    final active = buildVisibleRangeActiveCandidates(range: range, presets: [preset('builtin.image', {image})]);
    expect(active.first.isGallery, isTrue, reason: 'the result preview comes first');
    expect(active[1].preset?.id, 'builtin.image');
    expect(active.skip(2).map((candidate) => candidate.id), ['r1', 's1'], reason: 'evaluation order, and disabled rules stay out');
  });

  test('the active section omits an unrestricted base', () {
    final active = buildVisibleRangeActiveCandidates(range: VisibleRange.emptyGallery(), presets: const []);
    expect(active.map((candidate) => candidate.isGallery), [true], reason: 'the gallery preview already means "everything"');
  });
}
