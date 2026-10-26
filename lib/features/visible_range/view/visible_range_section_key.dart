import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

/// Section headers of the visible-range grid.
///
/// The step count is part of the title: the album grid's header has no count
/// slot of its own, and the count is the cumulative result after that group,
/// not the number of tiles.
class VisibleRangeSectionKey extends ChipSectionKey {
  final VisibleRangeCandidateKind kind;
  final int? count;
  final bool supplementsOutside;

  new(BuildContext context, this.kind, {this.count, this.supplementsOutside = true}) : super(title: _title(context, kind, count, supplementsOutside));

  static String _title(BuildContext context, VisibleRangeCandidateKind kind, int? count, bool supplementsOutside) {
    final l10n = context.l10n;
    final name = switch (kind) {
      VisibleRangeCandidateKind.base => l10n.visibleRangeSectionBase,
      VisibleRangeCandidateKind.restriction => l10n.visibleRangeSectionRestrictions,
      VisibleRangeCandidateKind.supplement => supplementsOutside ? l10n.visibleRangeSectionSupplementsOutside : l10n.visibleRangeSectionSupplementsInside,
    };
    return count == null ? name : '$name · ${l10n.visibleRangeCount(count)}';
  }

  @override
  Widget? get leading => Icon(
        switch (kind) {
          VisibleRangeCandidateKind.base => AIcons.visibleRangeBase,
          VisibleRangeCandidateKind.restriction => AIcons.visibleRangeRestriction,
          VisibleRangeCandidateKind.supplement => AIcons.visibleRangeSupplement,
        },
      );

  @override
  List<Object?> get props => [...super.props, kind, count, supplementsOutside];
}
