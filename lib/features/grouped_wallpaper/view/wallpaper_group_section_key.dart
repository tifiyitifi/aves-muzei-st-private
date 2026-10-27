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
class WallpaperGroupSectionKey extends ChipSectionKey {
  new(BuildContext context)
      : super(
          title: context.l10n.wallpaperGroupsTitle,
          titleStyle: visibleRangeSectionTitleStyle(context),
        );

  @override
  bool get selectable => false;

  @override
  Widget? get leading => const Icon(AIcons.wallpaper);
}
