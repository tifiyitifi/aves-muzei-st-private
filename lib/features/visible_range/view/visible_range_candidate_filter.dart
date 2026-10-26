import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

/// Grid adapter for one visible-range candidate.
///
/// The album grid is typed on `CollectionFilter`, while a candidate is a set of
/// filters plus an activation state. This adapter lets the feature reuse the
/// album page's grid, query and selection without teaching upstream about the
/// feature's types. It is view-only and never persisted.
class VisibleRangeCandidateFilter extends CollectionFilter {
  static const type = 'visible_range_candidate';

  final VisibleRangeCandidate candidate;

  /// Footer copies are not part of the grid's selection: tapping one cancels
  /// the condition instead.
  final bool summary;

  late final EntryPredicate _test;

  new(this.candidate, {this.summary = false, super.reversed = false}) {
    final filters = candidate.filters;
    _test = filters.isEmpty ? (entry) => true : (entry) => filters.every((filter) => filter.test(entry));
  }

  @override
  EntryPredicate get positiveTest => _test;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel {
    if (candidate.labelKey.isNotEmpty) return candidate.labelKey;
    if (candidate.label.isNotEmpty) return candidate.label;
    final labels = candidate.filters.map((filter) => filter.universalLabel).where((label) => label.isNotEmpty).toList()..sort();
    return labels.join(' · ');
  }

  @override
  String getLabel(BuildContext context) => visibleRangeCandidateLabel(context, candidate);

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) {
    final icon = candidate.isUnrestricted
        ? AIcons.filterOff
        : switch (candidate.kind) {
            VisibleRangeCandidateKind.base => AIcons.visibleRangeBase,
            VisibleRangeCandidateKind.restriction => AIcons.visibleRangeRestriction,
            VisibleRangeCandidateKind.supplement => AIcons.visibleRangeSupplement,
          };
    return Icon(icon, size: size);
  }

  @override
  String get category => type;

  @override
  String get key => '$type-${summary ? 'summary' : 'grid'}-${candidate.id}-${candidate.active}';

  @override
  Map<String, Object?> toJsonMap() => {
        'type': type,
        'id': candidate.id,
        'summary': summary,
        'active': candidate.active,
        if (reversed) 'reversed': reversed,
      };

  @override
  List<Object?> get props => [candidate.id, summary, candidate.active, candidate.labelKey, candidate.label, candidate.filters, reversed];
}
