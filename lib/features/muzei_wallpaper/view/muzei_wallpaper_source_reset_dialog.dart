import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_reset_setting.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_confirm_dialog.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Asks before the source drops every My photos filter.
///
/// Resetting is one tap away from a filter set the user may have spent a while
/// building, so the action confirms by default. It only touches the My photos
/// filters: a single picture source keeps working as it is.
Future<bool> confirmWallpaperSourceReset(BuildContext context) {
  final l10n = context.l10n;
  return confirmWallpaperAction(
    context,
    title: l10n.muzeiWallpaperSourceResetTitle,
    message: l10n.muzeiWallpaperSourceResetMessage,
    confirmLabel: l10n.muzeiWallpaperSourcesUseAllPhotos,
    enabled: () => WallpaperSourceResetSetting.enabled,
    setEnabled: WallpaperSourceResetSetting.setEnabled,
  );
}
