import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The three tile sections of the visible-range page.
///
/// Base tiles are mutually exclusive, restrictions are AND-ed and supplements
/// OR-ed; the kind is part of the candidate so a tile never has to guess.
enum VisibleRangeCandidateKind {
  base,
  restriction,
  supplement;

  VisibleRangeRuleKind? get ruleKind => switch (this) {
        base => null,
        restriction => VisibleRangeRuleKind.restriction,
        supplement => VisibleRangeRuleKind.supplement,
      };
}

/// One tappable tile: the current base, a base preset, or a rule.
///
/// Inactive defaults are rules too (they are seeded switched off), so the page
/// renders every candidate from the same value instead of keeping two parallel
/// lists. [labelKey] is an ARB key for built-in names; [label] is user text.
@immutable
class VisibleRangeCandidate extends Equatable {
  static const unrestrictedId = 'base.unrestricted';
  static const customBaseId = 'base.custom';
  static const galleryId = 'gallery';

  final String id;
  final VisibleRangeCandidateKind kind;
  final Set<CollectionFilter> filters;
  final String labelKey;
  final String label;
  final String description;
  final bool active;
  final VisibleRangePreset? preset;
  final VisibleRangeRule? rule;

  const new({
    required this.id,
    required this.kind,
    required this.filters,
    this.labelKey = '',
    this.label = '',
    this.description = '',
    this.active = false,
    this.preset,
    this.rule,
  });

  factory fromPreset(VisibleRangePreset preset, {required bool active}) => VisibleRangeCandidate(
        id: preset.id,
        kind: VisibleRangeCandidateKind.base,
        filters: preset.filters,
        labelKey: preset.builtin ? preset.name : '',
        label: preset.builtin ? '' : preset.name,
        description: preset.description,
        active: active,
        preset: preset,
      );

  /// A candidate for an active base whose preset was deleted: the range still
  /// carries its filters, so it must stay visible and selected.
  ///
  /// Like a rule label, a name starting with `@` is an ARB key (a wallpaper
  /// group's bundled base name); anything else is user text.
  factory customBase({required String name, required Set<CollectionFilter> filters}) {
    final isKey = name.startsWith('@');
    return VisibleRangeCandidate(
      id: customBaseId,
      kind: VisibleRangeCandidateKind.base,
      filters: filters,
      labelKey: isKey ? name.substring(1) : '',
      label: isKey ? '' : name,
      active: true,
    );
  }

  factory fromRule(VisibleRangeRule rule) {
    final rawLabel = rule.label;
    final isKey = rawLabel.startsWith('@');
    return VisibleRangeCandidate(
      id: rule.id,
      kind: rule.kind == VisibleRangeRuleKind.restriction ? VisibleRangeCandidateKind.restriction : VisibleRangeCandidateKind.supplement,
      filters: rule.filters,
      labelKey: isKey ? rawLabel.substring(1) : '',
      label: isKey ? '' : rawLabel,
      description: rule.description,
      active: rule.active,
      rule: rule,
    );
  }

  static const unrestricted = VisibleRangeCandidate(
    id: unrestrictedId,
    kind: VisibleRangeCandidateKind.base,
    filters: {},
    labelKey: 'visibleRangeUnrestricted',
    active: true,
  );

  /// The result preview: the range itself, not one of its conditions.
  ///
  /// Its stats are the range's result stats, so it is never selected, toggled or
  /// removed like a condition.
  static const gallery = VisibleRangeCandidate(
    id: galleryId,
    kind: VisibleRangeCandidateKind.base,
    filters: {},
    labelKey: 'visibleRangeGallery',
    active: true,
  );

  bool get isUnrestricted => id == unrestrictedId;

  bool get isGallery => id == galleryId;

  bool get isBuiltinRule => rule != null && isVisibleRangeBuiltinRule(rule!.id);

  /// Key of the preview statistics: the filter set, not the tile identity, so
  /// the same conditions share one count and one cover.
  String get statsKey => filterFingerprint(filters);

  @override
  List<Object?> get props => [id, kind, filters, labelKey, label, description, active];
}

/// A titled group of candidates.
@immutable
class VisibleRangeCandidateSection extends Equatable {
  final VisibleRangeCandidateKind kind;
  final List<VisibleRangeCandidate> candidates;

  const new({required this.kind, required this.candidates});

  @override
  List<Object?> get props => [kind, candidates];
}

/// Builds the page's three sections from the stored range and presets.
List<VisibleRangeCandidateSection> buildVisibleRangeSections({
  required VisibleRange range,
  required List<VisibleRangePreset> presets,
}) {
  final presetIds = presets.map((preset) => preset.id).toSet();
  final base = <VisibleRangeCandidate>[
    range.isBaseUnrestricted ? VisibleRangeCandidate.unrestricted : VisibleRangeCandidate.unrestricted.copyWithActive(false),
    if (!range.isBaseUnrestricted && (range.basePresetId.isEmpty || !presetIds.contains(range.basePresetId)))
      VisibleRangeCandidate.customBase(name: range.baseName, filters: range.baseFilters),
    for (final preset in presets)
      VisibleRangeCandidate.fromPreset(
        preset,
        active: !range.isBaseUnrestricted && range.basePresetId == preset.id,
      ),
  ];

  List<VisibleRangeCandidate> rulesOf(VisibleRangeRuleKind kind) {
    final rules = range.rules.where((rule) => rule.kind == kind).toList()
      ..sort((a, b) {
        // Defaults keep the asset order and stay ahead of user rules, whose
        // positions may predate the seeded defaults.
        final aBuiltin = isVisibleRangeBuiltinRule(a.id);
        final bBuiltin = isVisibleRangeBuiltinRule(b.id);
        if (aBuiltin != bBuiltin) return aBuiltin ? -1 : 1;
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });
    return [for (final rule in rules) VisibleRangeCandidate.fromRule(rule)];
  }

  final baseSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.base, candidates: base);
  final restrictionSection = VisibleRangeCandidateSection(
    kind: VisibleRangeCandidateKind.restriction,
    candidates: rulesOf(VisibleRangeRuleKind.restriction),
  );
  final supplementSection = VisibleRangeCandidateSection(
    kind: VisibleRangeCandidateKind.supplement,
    candidates: rulesOf(VisibleRangeRuleKind.supplement),
  );
  // The display follows the evaluation order, like the old scenario page: the
  // group applied first comes first. The base is always the first group.
  return [
    baseSection,
    if (range.order.isIntersectFirst) ...[restrictionSection, supplementSection] else ...[supplementSection, restrictionSection],
  ];
}

/// The active conditions repeated as the page's last section.
///
/// It reads top-down like the range evaluates: the result preview first, then the
/// active base, then the active rules in evaluation order. The unrestricted base
/// is left out because the result preview already stands for "everything".
List<VisibleRangeCandidate> buildVisibleRangeActiveCandidates({
  required VisibleRange range,
  required List<VisibleRangePreset> presets,
}) {
  final baseCandidates = buildVisibleRangeSections(range: range, presets: presets).first.candidates;
  final activeBase = baseCandidates.firstWhereOrNull((candidate) => candidate.active && !candidate.isUnrestricted);
  final rules = [
    for (final kind in range.order.isIntersectFirst
        ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
        : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
      for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
  ];
  return [
    VisibleRangeCandidate.gallery,
    ?activeBase,
    ...rules,
  ];
}

extension on VisibleRangeCandidate {
  VisibleRangeCandidate copyWithActive(bool active) => VisibleRangeCandidate(
        id: id,
        kind: kind,
        filters: filters,
        labelKey: labelKey,
        label: label,
        description: description,
        active: active,
      );
}
