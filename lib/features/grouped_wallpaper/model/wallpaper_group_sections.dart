import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';

/// Candidate id of the wallpaper page's per-group 「无 filters」 control.
const String wallpaperGroupNoFiltersId = 'wallpaper.group.noFilters';

/// Candidate id prefix of an empty restriction/supplement section.
const String wallpaperGroupSectionNoneIdPrefix = 'wallpaper.group.sectionNone.';

VisibleRangeCandidate _noFilters({required bool active}) => VisibleRangeCandidate(
      id: wallpaperGroupNoFiltersId,
      kind: VisibleRangeCandidateKind.base,
      filters: const {},
      labelKey: 'wallpaperGroupNoFilters',
      active: active,
      placeholder: true,
    );

VisibleRangeCandidate _sectionNone(VisibleRangeCandidateKind kind) => VisibleRangeCandidate(
      id: '$wallpaperGroupSectionNoneIdPrefix${kind.name}',
      kind: kind,
      filters: const {},
      labelKey: 'wallpaperGroupSectionNone',
      placeholder: true,
    );

/// Whether [candidate] is the group's own base, as opposed to the 「无 filters」
/// control or a section placeholder.
bool isWallpaperGroupBaseCandidate(VisibleRangeCandidate candidate) =>
    candidate.kind == VisibleRangeCandidateKind.base && !candidate.placeholder && candidate.id == VisibleRangeCandidate.customBaseId;

/// The group page's sections, built from the group's own range only.
///
/// The gallery's preset catalogue never enters this builder: a group owns its
/// base and its rules, and conditions are added by pinning from a media set,
/// never by picking a gallery default here. The base section always starts with
/// the 「无 filters」 control, and an empty rule section keeps one 「None」 slot so
/// the page shows that the section exists instead of hiding it.
List<VisibleRangeCandidateSection> buildWallpaperGroupSections({required VisibleRange range}) {
  final baseActive = range.baseActive && range.baseFilters.isNotEmpty;
  final anyRuleActive = range.rules.any((rule) => rule.active && rule.filters.isNotEmpty);
  final base = <VisibleRangeCandidate>[
    _noFilters(active: !baseActive && !anyRuleActive),
    if (range.baseFilters.isNotEmpty)
      VisibleRangeCandidate.customBase(name: range.baseName, filters: range.baseFilters, active: range.baseActive),
  ];

  List<VisibleRangeCandidate> rulesOf(VisibleRangeRuleKind kind) {
    final rules = range.rulesOf(kind);
    if (rules.isEmpty) {
      return [
        _sectionNone(
          kind == VisibleRangeRuleKind.restriction ? VisibleRangeCandidateKind.restriction : VisibleRangeCandidateKind.supplement,
        ),
      ];
    }
    return [for (final rule in rules) VisibleRangeCandidate.fromRule(rule)];
  }

  final baseSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.base, candidates: base);
  final restrictionSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.restriction, candidates: rulesOf(VisibleRangeRuleKind.restriction));
  final supplementSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.supplement, candidates: rulesOf(VisibleRangeRuleKind.supplement));
  return [
    baseSection,
    if (range.order.isIntersectFirst) ...[restrictionSection, supplementSection] else ...[supplementSection, restrictionSection],
  ];
}

/// The group's active conditions, for the page's active footer/section.
///
/// The result preview comes first, then the active base (only when it takes
/// part), then the active rules in evaluation order.
List<VisibleRangeCandidate> buildWallpaperGroupActiveCandidates({required VisibleRange range}) {
  final base = range.baseActive && range.baseFilters.isNotEmpty
      ? VisibleRangeCandidate.customBase(name: range.baseName, filters: range.baseFilters)
      : null;
  final rules = [
    for (final kind in range.order.isIntersectFirst
        ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
        : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
      for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
  ];
  return [
    VisibleRangeCandidate.gallery,
    ?base,
    ...rules,
  ];
}
