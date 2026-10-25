import 'dart:async';

import 'package:aves/features/collection_paging/view/viewer_delete_policy.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_delete_settings.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/features/muzei_wallpaper/services/wallpaper_controller.dart';
import 'package:aves/features/muzei_wallpaper/view/wallpaper_confirm_dialog.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Delete semantics for the viewer opened from the wallpaper page.
///
/// The single source keeps a private copy, and the viewer may be showing either
/// the library original (when it still exists) or that copy. Deleting the
/// original keeps the wallpaper working through the copy; deleting the copy
/// stops the source, so the dialogs say which is which.
class WallpaperViewerDeletePolicy implements ViewerDeletePolicy {
  final WallpaperController controller;

  const new(this.controller);

  @override
  bool get replacesStandardConfirmation => controller.prefs.scope.kind == WallpaperSourceKind.single;

  @override
  bool isPrivateCopy(AvesEntry entry) {
    final scope = controller.prefs.scope;
    if (scope.kind != WallpaperSourceKind.single) return false;
    final artwork = scope.singleArtwork;
    if (artwork == null) return false;
    final file = controller.singleArtworkStore.resolve(artwork.relativePath);
    return entry.path == file.path || entry.uri == file.uri.toString();
  }

  @override
  Future<bool> confirmDelete(BuildContext context, AvesEntry entry) {
    final scope = controller.prefs.scope;
    // Photos are advanced by the queue; only a single picture changes what the
    // source can show next, so only there does deleting ask.
    if (scope.kind != WallpaperSourceKind.single) return Future.value(true);

    final copy = isPrivateCopy(entry);
    final l10n = context.l10n;
    return confirmWallpaperAction(
      context,
      title: copy ? l10n.muzeiWallpaperViewerDeleteCopyTitle : l10n.muzeiWallpaperViewerDeleteOriginalTitle,
      message: copy ? l10n.muzeiWallpaperViewerDeleteCopyMessage : l10n.muzeiWallpaperViewerDeleteOriginalMessage,
      confirmLabel: l10n.deleteButtonLabel,
      enabled: copy ? () => WallpaperSourceDeleteSetting.enabled : () => WallpaperViewerDeleteSetting.enabled,
      setEnabled: copy ? WallpaperSourceDeleteSetting.setEnabled : WallpaperViewerDeleteSetting.setEnabled,
    );
  }

  @override
  Future<bool> deletePrivateCopy(BuildContext context, AvesEntry entry) async {
    if (!isPrivateCopy(entry)) return false;

    final removed = await controller.removeSingleCopy(scope: controller.prefs.scope.copyWith(clearSingleArtwork: true));
    if (!context.mounted) return true;
    if (!removed) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.genericFailureFeedback)),
      );
      return true;
    }
    // The file on screen no longer exists, so leave the viewer.
    Navigator.maybeOf(context)?.pop();
    return true;
  }

  @override
  void onDeleted(AvesEntry entry) {
    if (controller.prefs.scope.kind == WallpaperSourceKind.myPhotos) {
      unawaited(controller.advance());
    }
    // A single original leaves the copy untouched, so the wallpaper keeps
    // working and must not move to another artwork.
  }
}
