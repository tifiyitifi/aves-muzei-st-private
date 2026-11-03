import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_pad_config.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The icon and the label of a pad action.
///
/// Shared by the live pad's tooltips and the editor, so the two never describe
/// the same action with two different names.
IconData groupedWallpaperPadActionIcon(GroupedWallpaperPadAction action) => switch (action) {
  GroupedWallpaperPadAction.previousPhoto => AIcons.previousArtwork,
  GroupedWallpaperPadAction.nextPhoto => AIcons.nextArtwork,
  GroupedWallpaperPadAction.more => AIcons.more,
  GroupedWallpaperPadAction.nextGroup => AIcons.up,
  GroupedWallpaperPadAction.previousGroup => AIcons.down,
  GroupedWallpaperPadAction.delete => AIcons.delete,
  GroupedWallpaperPadAction.openGroups => AIcons.wallpaper,
  GroupedWallpaperPadAction.openInGallery => AIcons.image,
  GroupedWallpaperPadAction.viewWholeGroup => AIcons.allCollection,
  GroupedWallpaperPadAction.share => AIcons.share,
  GroupedWallpaperPadAction.history => AIcons.history,
  GroupedWallpaperPadAction.autoAdvance => AIcons.autoAdvance,
  GroupedWallpaperPadAction.effects => AIcons.palette,
  GroupedWallpaperPadAction.gestures => AIcons.gestures,
  GroupedWallpaperPadAction.switchSurface => AIcons.visibleRangeActive,
  GroupedWallpaperPadAction.toggleNotification => AIcons.checked,
  GroupedWallpaperPadAction.disableWallpaper => AIcons.wallpaperStopped,
  GroupedWallpaperPadAction.toggleLock => AIcons.locked,
  GroupedWallpaperPadAction.about => AIcons.info,
};

String groupedWallpaperPadActionLabel(BuildContext context, GroupedWallpaperPadAction action) {
  final l10n = context.l10n;
  return switch (action) {
    GroupedWallpaperPadAction.previousPhoto => l10n.wallpaperGroupPreviousPhoto,
    GroupedWallpaperPadAction.nextPhoto => l10n.wallpaperGroupNextPhoto,
    GroupedWallpaperPadAction.more => l10n.groupedWallpaperPadActionMore,
    GroupedWallpaperPadAction.nextGroup => l10n.wallpaperGroupNextGroup,
    GroupedWallpaperPadAction.previousGroup => l10n.wallpaperGroupPreviousGroup,
    GroupedWallpaperPadAction.delete => l10n.groupedWallpaperViewDelete,
    GroupedWallpaperPadAction.openGroups => l10n.groupedWallpaperViewOpenGroups,
    GroupedWallpaperPadAction.openInGallery => l10n.groupedWallpaperViewOpenInGallery,
    GroupedWallpaperPadAction.viewWholeGroup => l10n.groupedWallpaperViewWholeGroup,
    GroupedWallpaperPadAction.share => l10n.groupedWallpaperViewShare,
    GroupedWallpaperPadAction.history => l10n.wallpaperGroupHistoryTitle,
    GroupedWallpaperPadAction.autoAdvance => l10n.muzeiWallpaperAutoAdvance,
    GroupedWallpaperPadAction.effects => l10n.muzeiWallpaperEffects,
    GroupedWallpaperPadAction.gestures => l10n.wallpaperGroupGestures,
    GroupedWallpaperPadAction.switchSurface => l10n.groupedWallpaperPadActionSwitchSurface,
    GroupedWallpaperPadAction.toggleNotification => l10n.wallpaperGroupNotification,
    GroupedWallpaperPadAction.disableWallpaper => l10n.wallpaperGroupDisableWallpaper,
    GroupedWallpaperPadAction.toggleLock => l10n.groupedWallpaperPadActionToggleLock,
    GroupedWallpaperPadAction.about => l10n.aboutWallpaperTitle,
  };
}
