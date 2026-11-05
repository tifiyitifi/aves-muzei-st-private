import 'package:aves/features/album_contents_transfer/model/album_contents_rename_plan.dart';
import 'package:aves/features/album_contents_transfer/services/album_directory_rename_service.dart';
import 'package:aves/features/album_contents_transfer/services/album_rename_outcome_applier.dart';
import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// How many rows an album has to hold before asking the user to grant folder
/// access is worth an extra system dialog. Below it the batched move finishes
/// quickly enough, and the grant would outlive this one rename.
const _proactiveSafGrantThreshold = 500;

/// Renames the album's folder in one call when the platform can do it, and
/// carries the database rows and the album state over.
///
/// Three strategies, in order: app-private storage (the vault), a SAF grant,
/// then one Media Store update per collection. The first two move the whole
/// folder; the third moves the direct children, exactly what the batched move
/// does. All of them keep the row ids that favourites, covers and pins are
/// keyed on.
///
/// Answers false when the caller must keep the batched move: no strategy
/// applies, the platform refused, or a folder with that name exists (the
/// batched move merges into it, which a rename cannot). Everything the folder
/// holds moves with it, which is why the rename guard refuses an album whose
/// folder holds items the view does not show.
Future<bool> renameAlbumDirectoryInstantly(
  BuildContext context, {
  required StoredAlbumFilter filter,
  required AlbumContentsRenamePlan plan,
  required EntrySetActionDelegate delegate,
}) async {
  final newName = pContext.basename(plan.destination);
  var outcome = await albumDirectoryRenameService.renameAlbumDirectory(album: plan.album, newName: newName);

  if (!outcome.succeeded && outcome.failure == AlbumDirectoryRenameFailure.unsupported && !filter.isVault) {
    // A large album is worth one system dialog: the grant turns a long, visible
    // move into a single folder rename, and a refusal only costs the prompt.
    outcome = await _requestFolderAccessAndRetry(context, plan: plan, newName: newName) ?? outcome;
  }

  if (outcome.failure == AlbumDirectoryRenameFailure.partial) {
    // The platform moved some rows and kept their ids. Catch the database up
    // before the batched path reads the old folder, or it would try to move
    // files already sitting in the destination and report them as missing.
    await pagedDiscoverer.syncIfChanged();
    return false;
  }

  if (!outcome.succeeded) return false;

  final source = context.read<CollectionSource>();
  final rowsMoved = await applyInstantAlbumRename(
    source: source,
    album: plan.album,
    destination: plan.destination,
  );
  if (context.mounted) {
    delegate.showFeedback(
      context,
      rowsMoved ? FeedbackType.info : FeedbackType.warn,
      rowsMoved ? context.l10n.genericSuccessFeedback : context.l10n.genericFailureFeedback,
    );
  }
  return true;
}

/// Offers to grant SAF access to the album's parent, then retries the native
/// rename once.
///
/// Answers null when the flow does not apply or the user declined, so the
/// caller keeps its batched move. The request is only made when the platform
/// says the directory is selectable: Downloads and the `Android` folder are
/// refused on Android 11+, and a picker that cannot grant them would only
/// confuse.
Future<AlbumDirectoryRenameOutcome?> _requestFolderAccessAndRetry(
  BuildContext context, {
  required AlbumContentsRenamePlan plan,
  required String newName,
}) async {
  if (await localMediaDb.countInDirectory(plan.album) < _proactiveSafGrantThreshold) return null;

  final request = await storagePermissionService.getSafDirectoryToRequest(pContext.dirname(plan.album));
  if (request == null) return null;
  if (!context.mounted) return null;

  final confirmed = await showConfirmationDialog(
    context: context,
    message: context.l10n.albumRenameGrantFolderAccess,
    // Reuses the collection's "Grant access" label: the further system dialog
    // is the actual permission step, this one only explains why.
    ok: context.l10n.collectionEmptyGrantAccessButtonLabel,
  );
  if (!confirmed || !context.mounted) return null;

  if (!await deviceService.isSystemFilePickerEnabled()) return null;
  if (!context.mounted) return null;

  final granted = await storagePermissionService.requestSafMediaDirectoryAccess(request.dirPath);
  if (!granted) return null;

  // The picker lets the user choose any folder: only a grant covering the
  // album makes the rename instant.
  final albumWithSeparator = '${plan.album}${pContext.separator}';
  final grantedDirs = await storagePermissionService.getSafGrantedDirectories();
  if (!grantedDirs.any(albumWithSeparator.startsWith)) return null;

  return albumDirectoryRenameService.renameAlbumDirectory(album: plan.album, newName: newName);
}
