import 'package:aves/features/album_contents_transfer/services/album_rename_visibility_probe.dart';
import 'package:aves/features/album_contents_transfer/view/album_contents_transfer_action.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/album_set.dart';
import 'package:flutter/widgets.dart';

/// Whether a stored album rename may go ahead, saying why when it may not.
///
/// Renaming an album renames its folder, so it moves everything the folder
/// holds. A rename over a narrowed view would either take items the user cannot
/// see or split the album in two, so the two behaviours are kept apart: the
/// rename is refused, and the user is offered the transfer, which is defined
/// over the visible set by construction.
///
/// A vault cannot offer that: contents leaving a vault would expose it, so its
/// albums only get the explanation.
Future<bool> allowStoredAlbumRename(
  BuildContext context,
  StoredAlbumFilter filter, {
  required AlbumChipSetActionDelegate delegate,
}) async {
  final visibility = await probeAlbumRenameVisibility(filter);
  if (visibility == null || visibility.coversAlbum) return true;
  if (!context.mounted) return false;

  final message = context.l10n.albumRenameUnseenContents(visibility.unseen);
  final canMove = !filter.isVault && VisibleRangeGate.allows(VisibleRangeMutation.move);
  if (!canMove) {
    await showWarningDialog(context: context, message: message);
    return false;
  }

  final moveInstead = await showConfirmationDialog(
    context: context,
    message: message,
    ok: context.l10n.albumContentsMoveAction,
  );
  if (!context.mounted) return false;
  if (moveInstead) await moveAlbumContentsToAnotherAlbum(context, filter, delegate: delegate);
  // The rename itself never runs on a narrowed album, whichever way the user
  // answered: the folder and the view disagree, and only a move is defined.
  return false;
}
