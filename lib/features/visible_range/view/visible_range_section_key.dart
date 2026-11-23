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

  /// Whether the section belongs to the scope-wide outside pool.
  ///
  /// The outside pool has no source role, so only the two rule titles change.
  final bool outside;

  new(BuildContext context, this.kind, {this.countText = '', this.outside = false})
      : super(
          title: _title(context, kind, countText, outside),
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  static String _title(BuildContext context, VisibleRangeCandidateKind kind, String countText, bool outside) {
    final l10n = context.l10n;
    final name = switch (kind) {
      VisibleRangeCandidateKind.base => l10n.visibleRangeSectionBase,
      VisibleRangeCandidateKind.restriction => outside ? l10n.visibleRangeSectionOutsideRestrictions : l10n.visibleRangeSectionRestrictions,
      VisibleRangeCandidateKind.supplement => outside ? l10n.visibleRangeSectionOutsideSupplements : l10n.visibleRangeSectionSupplements,
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
  List<Object?> get props => [...super.props, kind, countText, outside];
}

/// Header of the mutually exclusive groups section.
///
/// A group is a container, not a condition: the header names the section and
/// counts how many groups the scope has.
class VisibleRangeGroupSectionKey extends ChipSectionKey {
  final String countText;

  new(BuildContext context, {this.countText = ''})
      : super(
          title: countText.isEmpty ? context.l10n.visibleRangeSectionGroups : '${context.l10n.visibleRangeSectionGroups} $countText',
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  @override
  Widget? get leading => const Icon(Icons.layers_outlined);

  @override
  List<Object?> get props => [...super.props, countText];
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

/// Header of the active-conditions section, shown as the page's last group.
///
/// It is the same section header as the three candidate groups, with the lamp as
/// its leading icon and the restricted state on the right. It never starts a
/// selection: its tiles summarize conditions that are already selectable above.
class VisibleRangeActiveSectionKey extends ChipSectionKey {
  final bool restricted;

  new(BuildContext context, {required this.restricted})
      : super(
          title: context.l10n.visibleRangeSectionCurrent,
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  @override
  bool get selectable => false;

  @override
  Widget? get leading => const Icon(AIcons.visibleRangeActive);

  @override
  Widget buildTrailing(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Text(
      restricted ? context.l10n.visibleRangeRestricted : context.l10n.visibleRangeUnrestricted,
      style: theme.textTheme.labelLarge?.copyWith(color: restricted ? colors.error : colors.primary),
    );
  }

  @override
  List<Object?> get props => [...super.props, restricted];
}
