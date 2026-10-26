import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/styles.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

/// Section headers of the visible-range grid.
///
/// The trailing text describes the group itself, not the entries it leaves
/// visible: the base group shows how many choices it offers, and the rule groups
/// show `active/total`. The resulting item total belongs to the footer's gallery
/// chip.
class VisibleRangeSectionKey extends ChipSectionKey {
  final VisibleRangeCandidateKind kind;
  final String countText;
  final bool supplementsOutside;

  new(BuildContext context, this.kind, {this.countText = '', this.supplementsOutside = true})
      : super(
          title: _title(context, kind, countText, supplementsOutside),
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  static String _title(BuildContext context, VisibleRangeCandidateKind kind, String countText, bool supplementsOutside) {
    final l10n = context.l10n;
    final name = switch (kind) {
      VisibleRangeCandidateKind.base => l10n.visibleRangeSectionBase,
      VisibleRangeCandidateKind.restriction => l10n.visibleRangeSectionRestrictions,
      VisibleRangeCandidateKind.supplement => supplementsOutside ? l10n.visibleRangeSectionSupplementsOutside : l10n.visibleRangeSectionSupplementsInside,
    };
    return countText.isEmpty ? name : '$name $countText';
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
  List<Object?> get props => [...super.props, kind, countText, supplementsOutside];
}

/// Lower-case section titles without the app-wide small-caps effect.
///
/// The visible-range page reads as a plain checklist, so its headers drop the
/// letter spacing and the small-caps font feature used elsewhere. Other pages
/// keep the default section style.
TextStyle visibleRangeSectionTitleStyle(BuildContext context) => AStyles.sectionTitleStyle(context.knownLocale).copyWith(
      fontWeight: FontWeight.normal,
      letterSpacing: 0,
      fontFeatures: const [],
    );
