import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:material_ui/material_ui.dart';

/// Header of one surface's summary section on the wallpaper page.
///
/// The page ends with the two surfaces side by side: the lamp marks the one whose
/// marks the tiles above edit, and the other one still shows what it applies, so
/// the user can compare without switching. Its own tiles are read-only.
class WallpaperGroupSurfaceSectionKey extends ChipSectionKey {
  final WallpaperSurface surface;
  final bool active;
  final String countText;

  new(
    BuildContext context, {
    required this.surface,
    required this.active,
    this.countText = '',
  }) : super(
         title: _title(context, surface, countText),
         titleStyle: visibleRangeSectionTitleStyle(context),
       );

  static String _title(BuildContext context, WallpaperSurface surface, String countText) {
    final l10n = context.l10n;
    final name = surface.isLock ? l10n.wallpaperGroupSurfaceLockRange : l10n.wallpaperGroupSurfaceHomeRange;
    return countText.isEmpty ? name : '$name $countText';
  }

  @override
  Widget? get leading => Icon(active ? AIcons.visibleRangeActive : AIcons.visibleRangeInactive);

  @override
  bool get selectable => false;

  @override
  List<Object?> get props => [...super.props, surface, active, countText];
}
