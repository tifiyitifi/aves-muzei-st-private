import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_availability_label.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

/// The group section of the wallpaper page.
///
/// It is the page's first real section, so the group cards share the layout,
/// tile size and pinch zoom of the range below them. It never starts a
/// selection: a group selects which range is edited, it is not a condition.
///
/// In the sections switcher style this header is also where the availability
/// label lives: the cards below it are the switcher, so the state line has no
/// separate row to sit in.
class WallpaperGroupSectionKey extends ChipSectionKey {
  /// Whether the page temporarily ignores the gallery range.
  final bool gallerySuspended;

  new(BuildContext context, {this.gallerySuspended = false})
      : super(
          title: context.l10n.wallpaperGroupsTitle,
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  @override
  List<Object?> get props => [...super.props, gallerySuspended];

  @override
  bool get selectable => false;

  @override
  Widget? get leading => const Icon(AIcons.wallpaper);

  @override
  Widget? buildTrailing(BuildContext context) => WallpaperGroupAvailabilityLabel(gallerySuspended: gallerySuspended);
}
