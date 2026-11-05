import 'package:aves/features/album_contents_transfer/model/album_contents_rename_plan.dart';
import 'package:aves/features/album_contents_transfer/services/album_directory_rename_service.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

const _log = AreaKeyLog('log.album_contents_transfer');

/// Renames the album's folder in one call when the app owns it, and carries the
/// database rows and the album state over.
///
/// Only app-private storage qualifies (the vault, under `filesDir`). Shared
/// storage needs a bulk Media Store `RELATIVE_PATH` update or a SAF document
/// rename: `File.renameTo` there bypasses the Media Store and changes the row
/// ids that favourites, covers and pins are keyed on.
///
/// Answers false when the caller must keep the batched move: the album is not
/// app-private, the platform refused, or a folder with that name exists (the
/// batched move merges into it, which a rename cannot). Everything the folder
/// holds moves with it, which is why the rename guard refuses an album whose
/// folder holds items the view does not show.
Future<bool> renameAppPrivateAlbumDirectory(
  BuildContext context, {
  required StoredAlbumFilter filter,
  required AlbumContentsRenamePlan plan,
  required EntrySetActionDelegate delegate,
}) async {
  if (!filter.isVault) return false;

  final outcome = await albumDirectoryRenameService.renameAppPrivateDirectory(
    album: plan.album,
    newName: pContext.basename(plan.destination),
  );
  if (!outcome.succeeded) return false;

  final source = context.read<CollectionSource>();
  try {
    await localMediaDb.renameDirectoryPrefix(oldDirectory: plan.album, newDirectory: plan.destination);
  } catch (error, stack) {
    // The files moved but the rows did not. The album state below still follows
    // the folder, and a later scan re-reads the paths, so the library converges
    // on its own; the user is told instead of being shown a silent partial.
    _log.e('failed to move rows after renaming ${plan.album}', error, stack);
    if (context.mounted) {
      delegate.showFeedback(context, FeedbackType.warn, context.l10n.genericFailureFeedback);
    }
  }

  // Cover, group membership, pin, bookmarks and the vault metadata all follow
  // the folder, in the same order the batched path applies them.
  await source.applyStoredAlbumRename(plan.album, plan.destination);
  // The album list and its counts come from the summaries, which reload only
  // on a lens resolve: without this the page keeps the old name until re-entry.
  await reloadPagedSummaries();

  if (context.mounted) {
    delegate.showFeedback(context, FeedbackType.info, context.l10n.genericSuccessFeedback);
  }
  return true;
}
