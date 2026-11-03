import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/mime.dart';

/// Candidate id prefix of an empty restriction/supplement section.
const String wallpaperGroupSectionNoneIdPrefix = 'wallpaper.group.sectionNone.';

/// The wallpaper page's base choice: every image.
///
/// It is the same choice as 「Unrestricted」 on the gallery page — the group's
/// base narrows nothing — so it keeps that id and stays non-applicable. Its
/// filter set is images only, because a wallpaper never shows videos, and that
/// is also what makes its cover and count agree with the group cards (both
/// count images).
VisibleRangeCandidate wallpaperGroupAllImagesCandidate({required bool active}) => VisibleRangeCandidate(
  id: VisibleRangeCandidate.unrestrictedId,
  kind: VisibleRangeCandidateKind.base,
  filters: {MimeFilter.image},
  labelKey: 'wallpaperGroupAllImages',
  active: active,
);

VisibleRangeCandidate _sectionNone(VisibleRangeCandidateKind kind) => VisibleRangeCandidate(
  id: '$wallpaperGroupSectionNoneIdPrefix${kind.name}',
  kind: kind,
  filters: const {},
  labelKey: 'wallpaperGroupSectionNone',
  placeholder: true,
);

/// Whether [candidate] is the group's own base, as opposed to the
/// 「All images」 choice or a section placeholder.
bool isWallpaperGroupBaseCandidate(VisibleRangeCandidate candidate) => candidate.kind == VisibleRangeCandidateKind.base && !candidate.placeholder && candidate.id == VisibleRangeCandidate.customBaseId;

/// The group page's three condition sections, built from the group's pool.
///
/// Every condition appears exactly once, whatever surface marks it: home and
/// lock share the pool, so the sections are the pool's list, not a per-surface
/// copy. [active] decides which mark the tiles read as "on"; the other mark stays
/// visible on the tile.
///
/// The gallery's preset catalogue never enters this builder: a group owns its
/// base and its rules, and conditions are added by pinning from a media set,
/// never by picking a gallery default here. An empty rule section keeps one
/// 「None」 slot so the page shows that the section exists instead of hiding it.
List<VisibleRangeCandidateSection> buildWallpaperGroupPoolSections({required VisibleRange pool, required WallpaperSurface active}) {
  final usesBase = WallpaperConditionSurfaces.contains(pool.baseSurfaces, active);
  final base = <VisibleRangeCandidate>[
    wallpaperGroupAllImagesCandidate(active: !usesBase || pool.baseFilters.isEmpty),
    if (pool.baseFilters.isNotEmpty) VisibleRangeCandidate.customBase(name: pool.baseName, filters: pool.baseFilters).copyWithSurfaceMarks(surfaces: pool.baseSurfaces, active: usesBase),
  ];

  VisibleRangeCandidate fromRule(VisibleRangeRule rule) => VisibleRangeCandidate.fromRule(rule).copyWithSurfaceMarks(
    surfaces: rule.surfaces,
    active: WallpaperConditionSurfaces.contains(rule.surfaces, active),
  );

  List<VisibleRangeCandidate> rulesOf(VisibleRangeRuleKind kind) {
    final rules = pool.rulesOf(kind);
    if (rules.isEmpty) {
      return [
        _sectionNone(
          kind == VisibleRangeRuleKind.restriction ? VisibleRangeCandidateKind.restriction : VisibleRangeCandidateKind.supplement,
        ),
      ];
    }
    return [for (final rule in rules) fromRule(rule)];
  }

  final baseSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.base, candidates: base);
  final restrictionSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.restriction, candidates: rulesOf(VisibleRangeRuleKind.restriction));
  final supplementSection = VisibleRangeCandidateSection(kind: VisibleRangeCandidateKind.supplement, candidates: rulesOf(VisibleRangeRuleKind.supplement));
  return [
    baseSection,
    if (pool.order.isIntersectFirst) ...[restrictionSection, supplementSection] else ...[supplementSection, restrictionSection],
  ];
}

/// The conditions one surface actually applies, for the surface summary section.
///
/// The list is read-only: it says what that surface shows, and the pool sections
/// above are where the same conditions are edited. A surface that applies nothing
/// keeps one 「None」 slot so the section never collapses to an empty header.
///
/// [includeResult] prepends the result preview, so the lamped surface shows what
/// its conditions produce before listing them: the page uses it instead of a
/// separate "current range" section, which would repeat the same conditions.
List<VisibleRangeCandidate> buildWallpaperGroupSurfaceCandidates({required VisibleRange range, bool includeResult = false}) {
  final base = range.baseActive && range.baseFilters.isNotEmpty ? VisibleRangeCandidate.customBase(name: range.baseName, filters: range.baseFilters) : null;
  final conditions = [
    ?base,
    for (final kind in range.order.isIntersectFirst ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement] : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
      for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
  ];
  return [
    if (includeResult) VisibleRangeCandidate.gallery,
    if (conditions.isEmpty)
      const VisibleRangeCandidate(
        id: '${wallpaperGroupSectionNoneIdPrefix}surface',
        kind: VisibleRangeCandidateKind.base,
        filters: {},
        labelKey: 'wallpaperGroupSectionNone',
        placeholder: true,
      )
    else
      ...conditions,
  ];
}
