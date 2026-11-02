import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

/// One surface's section of the wallpaper page.
///
/// Both surfaces are expanded, but only the active one is editable; the inactive
/// sections keep the same candidate sections so the user can compare the two
/// ranges at a glance. The leading icon is the active/inactive marker.
class WallpaperGroupSurfaceSectionKey extends ChipSectionKey {
  final WallpaperSurface surface;
  final bool active;
  final VisibleRangeCandidateKind kind;
  final String countText;
  final bool supplementsOutside;

  new(
    BuildContext context, {
    required this.surface,
    required this.active,
    required this.kind,
    this.countText = '',
    this.supplementsOutside = true,
  }) : super(
          title: _title(context, surface, kind, countText, supplementsOutside),
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  static String _title(BuildContext context, WallpaperSurface surface, VisibleRangeCandidateKind kind, String countText, bool supplementsOutside) {
    final l10n = context.l10n;
    final surfaceName = surface.isLock ? l10n.wallpaperGroupSurfaceLock : l10n.wallpaperGroupSurfaceHome;
    final sectionName = switch (kind) {
      VisibleRangeCandidateKind.base => l10n.visibleRangeSectionBase,
      VisibleRangeCandidateKind.restriction => l10n.visibleRangeSectionRestrictions,
      VisibleRangeCandidateKind.supplement => supplementsOutside ? l10n.visibleRangeSectionSupplementsOutside : l10n.visibleRangeSectionSupplementsInside,
    };
    return countText.isEmpty ? '$surfaceName · $sectionName' : '$surfaceName · $sectionName $countText';
  }

  @override
  Widget? get leading => Icon(active ? AIcons.visibleRangeActive : AIcons.visibleRangeInactive);

  @override
  bool get selectable => false;

  @override
  List<Object?> get props => [...super.props, surface, active, kind, countText, supplementsOutside];
}
