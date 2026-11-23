import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The three condition sections of a range.
///
/// Base tiles are OR-ed with each other, restrictions are AND-ed and supplements
/// OR-ed; the kind is part of the candidate so a tile never has to guess.
enum VisibleRangeCandidateKind {
  base,
  restriction,
  supplement;

  VisibleRangeRuleKind? get ruleKind => switch (this) {
    base => VisibleRangeRuleKind.source,
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

  /// A tile that adds a new group instead of standing for a condition.
  static const groupAddId = 'group.add';

  final String id;
  final VisibleRangeCandidateKind kind;
  final Set<CollectionFilter> filters;
  final String labelKey;
  final String label;
  final String description;
  final bool active;
  final VisibleRangePreset? preset;
  final VisibleRangeRule? rule;

  /// The group a tile stands for, or empty for a condition tile.
  ///
  /// The gallery page lists the groups themselves as tiles: a group is a
  /// container, so it has no rule and its tap switches browsing instead of
  /// toggling a condition. The wallpaper page never sets it.
  final String groupId;

  /// A slot that only says "nothing here": an empty rule section, or the
  /// wallpaper page's "no filters" control. It is shown but is not a condition:
  /// it cannot be selected, opened, counted or deleted.
  final bool placeholder;

  /// Whether the tile is shown but cannot be edited.
  ///
  /// The wallpaper page uses it for a surface summary: it lists what that surface
  /// applies, and a tap there switches the edited surface instead of writing.
  final bool readOnly;

  /// Which wallpaper surfaces use this condition, as a bit mask.
  ///
  /// The wallpaper page draws the home/lock marks from it; the gallery page
  /// leaves it at `0`.
  final int surfaces;

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
    this.placeholder = false,
    this.readOnly = false,
    this.surfaces = 0,
    this.groupId = '',
  });

  /// A tile standing for a whole group.
  ///
  /// The filters are the group's resolved result, so the tile can show a cover
  /// and a count. Group 0 is 「Unrestricted」, the state the gallery starts in;
  /// its label is fixed, because naming it after a condition it never holds
  /// would be misleading.
  factory fromGroup(VisibleRange group, {required bool active, VisibleRange? outside}) {
    final isZero = group.id == VisibleRange.galleryRangeId;
    final rawName = group.name;
    final isKey = rawName.startsWith('@');
    final resolved = group.resolve(outside: outside);
    return VisibleRangeCandidate(
      id: group.id,
      kind: VisibleRangeCandidateKind.base,
      filters: resolved == null ? const {} : {resolved},
      labelKey: isZero ? 'visibleRangeUnrestricted' : (isKey ? rawName.substring(1) : ''),
      label: isZero || isKey ? '' : rawName,
      active: active,
      groupId: group.id,
    );
  }

  /// The trailing 「new group」 tile.
  static const addGroup = VisibleRangeCandidate(
    id: groupAddId,
    kind: VisibleRangeCandidateKind.base,
    filters: {},
    labelKey: 'visibleRangeGroupNew',
  );

  bool get isGroup => groupId.isNotEmpty;

  bool get isGroupAdd => id == groupAddId;

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
  factory customBase({required String name, required Set<CollectionFilter> filters, bool active = true}) {
    final isKey = name.startsWith('@');
    return VisibleRangeCandidate(
      id: customBaseId,
      kind: VisibleRangeCandidateKind.base,
      filters: filters,
      labelKey: isKey ? name.substring(1) : '',
      label: isKey ? '' : name,
      active: active,
    );
  }

  factory fromRule(VisibleRangeRule rule) {
    final rawLabel = rule.label;
    final isKey = rawLabel.startsWith('@');
    final kind = switch (rule.kind) {
      VisibleRangeRuleKind.source => VisibleRangeCandidateKind.base,
      VisibleRangeRuleKind.restriction => VisibleRangeCandidateKind.restriction,
      VisibleRangeRuleKind.supplement => VisibleRangeCandidateKind.supplement,
    };
    return VisibleRangeCandidate(
      id: rule.id,
      kind: kind,
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

  /// Whether the candidate can be taken out to a media set.
  ///
  /// The result preview and 「Unrestricted」 are not conditions, and an empty
  /// filter set would add nothing, so neither is a target. A read-only surface is
  /// a summary, not something the user can act on from the page. A group tile is
  /// a container: its tap switches browsing.
  bool get isApplicable => !isGallery && !isUnrestricted && !isGroup && !isGroupAdd && !placeholder && !readOnly && filters.isNotEmpty;

  bool get isBuiltinRule => rule != null && isVisibleRangeBuiltinRule(rule!.id);

  /// Key of the preview statistics: the filter set, not the tile identity, so
  /// the same conditions share one count and one cover.
  String get statsKey => filterFingerprint(filters);

  /// The same candidate in another activation state.
  ///
  /// Both base sections start from the constant [unrestricted] candidate and
  /// flip its state, so the 「Unrestricted」 tile reads and previews the same on
  /// either page.
  VisibleRangeCandidate copyWithActive(bool active) => VisibleRangeCandidate(
    id: id,
    kind: kind,
    filters: filters,
    labelKey: labelKey,
    label: label,
    description: description,
    active: active,
    preset: preset,
    rule: rule,
    placeholder: placeholder,
    readOnly: readOnly,
    surfaces: surfaces,
    groupId: groupId,
  );

  /// The same candidate with the wallpaper surface marks (and the mark the page
  /// reads as "on").
  VisibleRangeCandidate copyWithSurfaceMarks({required int surfaces, required bool active}) => VisibleRangeCandidate(
    id: id,
    kind: kind,
    filters: filters,
    labelKey: labelKey,
    label: label,
    description: description,
    active: active,
    preset: preset,
    rule: rule,
    placeholder: placeholder,
    readOnly: readOnly,
    surfaces: surfaces,
    groupId: groupId,
  );

  /// The same candidate, shown as a read-only summary.
  VisibleRangeCandidate copyWithReadOnly(bool readOnly) => VisibleRangeCandidate(
    id: id,
    kind: kind,
    filters: filters,
    labelKey: labelKey,
    label: label,
    description: description,
    active: active,
    preset: preset,
    rule: rule,
    placeholder: placeholder,
    readOnly: readOnly,
    surfaces: surfaces,
    groupId: groupId,
  );

  @override
  List<Object?> get props => [id, kind, filters, labelKey, label, description, active, placeholder, readOnly, surfaces, groupId];
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

/// Builds one group's three condition sections.
///
/// The gallery page's group tiles are built separately
/// (`buildVisibleRangePageSections`); this is what a group editor renders — a
/// group is a container, a candidate is a condition inside it.
List<VisibleRangeCandidateSection> buildVisibleRangeSections({required VisibleRange range}) {
  final sources = range.rulesOf(VisibleRangeRuleKind.source);
  final base = <VisibleRangeCandidate>[
    sources.isEmpty ? VisibleRangeCandidate.unrestricted : VisibleRangeCandidate.unrestricted.copyWithActive(false),
    for (final rule in sources) VisibleRangeCandidate.fromRule(rule),
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
/// group's active conditions, then the scope-wide outside conditions. The
/// unrestricted source is left out because the result preview already stands for
/// "everything".
List<VisibleRangeCandidate> buildVisibleRangeActiveCandidates({required VisibleRange range, VisibleRange? outside}) {
  final groupRules = [
    for (final kind in [VisibleRangeRuleKind.source, ...range.order.isIntersectFirst ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement] : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction]])
      for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
  ];
  // The outside layer is always intersect-first: restrictions first, then
  // supplements.
  final outsideRules = outside == null
      ? const <VisibleRangeCandidate>[]
      : [
          for (final kind in [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement])
            for (final rule in outside.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
        ];
  return [
    VisibleRangeCandidate.gallery,
    ...groupRules,
    ...outsideRules,
  ];
}
