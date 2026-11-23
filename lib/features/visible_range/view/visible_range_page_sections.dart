import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The gallery page's sections, in reading order.
///
/// The gallery is a list of mutually exclusive groups plus one scope-wide
/// outside pool; a group's own source/restriction/supplement conditions live in
/// its editor, not here. Keeping the layout in a pure builder makes the order
/// and the tile values testable without an app shell.
enum VisibleRangePageSectionKind {
  /// The mutually exclusive groups (group 0 is 「Unrestricted」), plus the
  /// 「new group」 tile.
  groups,

  /// The outside pool's active restrictions (AND).
  outsideRestriction,

  /// The outside pool's active supplements (OR).
  outsideSupplement,
}

/// A titled run of tiles on the gallery page.
@immutable
class VisibleRangePageSection extends Equatable {
  final VisibleRangePageSectionKind kind;
  final List<VisibleRangeCandidate> candidates;

  const new({required this.kind, required this.candidates});

  @override
  List<Object?> get props => [kind, candidates];
}

/// Builds the three sections above the result preview.
///
/// A group tile's filters are the group's browsed result (its own conditions
/// joined with the outside pool), so its cover and count are what switching to
/// it would show. The outside sections always read restrictions first: that
/// layer is evaluated intersection-first whatever the group's own order is.
List<VisibleRangePageSection> buildVisibleRangePageSections({
  required List<VisibleRange> groups,
  required String currentGroupId,
  required VisibleRange outside,
}) {
  final ordered = [...groups]..sort((a, b) => a.position.compareTo(b.position));
  final groupsSection = VisibleRangePageSection(
    kind: VisibleRangePageSectionKind.groups,
    candidates: [
      for (final group in ordered)
        if (group.kind == VisibleRangeGroupKind.group) VisibleRangeCandidate.fromGroup(group, active: group.id == currentGroupId, outside: outside),
      VisibleRangeCandidate.addGroup,
    ],
  );
  final outsideSections = buildVisibleRangeSections(range: outside).where((section) => section.kind != VisibleRangeCandidateKind.base).toList()
    ..sort(
      (a, b) => (a.kind == VisibleRangeCandidateKind.restriction ? 0 : 1).compareTo(b.kind == VisibleRangeCandidateKind.restriction ? 0 : 1),
    );
  return [
    groupsSection,
    for (final section in outsideSections)
      VisibleRangePageSection(
        kind: section.kind == VisibleRangeCandidateKind.restriction ? VisibleRangePageSectionKind.outsideRestriction : VisibleRangePageSectionKind.outsideSupplement,
        candidates: section.candidates,
      ),
  ];
}
