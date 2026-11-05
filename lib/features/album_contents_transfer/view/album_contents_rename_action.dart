import 'package:aves/features/album_contents_transfer/model/album_contents_rename_plan.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_entry_feed.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_scope.dart';
import 'package:aves/features/album_contents_transfer/view/album_instant_rename_action.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Renames a stored album on a windowed library.
///
/// Two ways, in order. A folder the app owns (the vault) is renamed by one
/// native call, and its rows follow it with a single prefix rewrite; anything
/// else moves the album's contents into a sibling folder. A library too large
/// to load holds no entries to hand to that move, so the album's visible scope
/// is resolved as the very predicate its tile counts (visible range, hidden
/// filters and locked vaults included) and walked in bounded batches, so the
/// album-level state that follows the rename still applies once, at the end,
/// exactly like the legacy path.
///
/// Answers false when the caller must keep its in-memory path: the source is
/// fully loaded, so the legacy code owns the same decision.
///
/// [filter] must already be unlocked; the caller owns the vault unlock step.
Future<bool> renameStoredAlbumFromDatabase(
  BuildContext context, {
  required StoredAlbumFilter filter,
  required String newName,
}) async {
  if (!await albumActionUsesDatabase(context)) return false;
  if (!context.mounted) return true;

  final plan = AlbumContentsRenamePlan.resolve(album: filter.album, newName: newName);
  // The rename dialog only submits a non-empty name, and replaying the current
  // name has nothing to move: both answer success without touching the library.
  if (plan.isNoOp || !plan.isValid) return true;

  final delegate = EntrySetActionDelegate();

  // A folder the app owns moves in one call, and the rows follow it: no batch,
  // no per-entry progress. Everything else keeps the batched move below.
  if (await renameAppPrivateAlbumDirectory(context, filter: filter, plan: plan, delegate: delegate)) return true;

  final scope = await AlbumContentsScope.resolve({filter});
  if (!context.mounted) return true;
  if (scope == null) {
    // The album needs the in-memory path, and the library holds too many
    // entries to load: say so instead of renaming nothing.
    await pagedScopeUnsupported(context);
    return true;
  }

  final source = context.read<CollectionSource>();
  var movedAny = false;

  if (scope.entryCount > 0) {
    final feed = AlbumContentsEntryFeed(
      albums: {filter},
      predicate: scope.predicate,
      count: scope.entryCount,
    );
    final summary = await runOverEntryFeed(context, feed, () async {
      final run = EntryFeedRun.current;
      final batch = run?.batch;
      if (run == null || batch == null || batch.isEmpty) return;
      // The legacy rename's guards (permissions, free space, undated items, name
      // conflicts) live inside `doQuickMove`; the run makes them ask once for the
      // whole album. The target folder is fresh, so names collide only when the
      // user merges into an existing album, which the legacy path allows too.
      final completed = await delegate.doQuickMove(
        context,
        moveType: MoveType.move,
        entriesByDestination: {plan.destination: batch.toSet()},
        // The legacy cleanup runs once, after every entry moved.
        cleanupEmptySourceDirectories: false,
      );
      if (!completed) {
        // A refused batch would fail identically on the next one: stop instead
        // of asking for the same permission once per batch.
        run.cancel();
      } else {
        movedAny = true;
      }
    });
    // The entries moved even if the page went away mid-run, so only the feedback
    // needs a live context: the album state below has to follow the rows.
    if (summary != null && context.mounted) {
      delegate.showFeedback(context, summary.type, summary.message, summary.action);
    }
  }

  // An empty album has no entries to move but still has state to carry (cover,
  // group membership, pin, bookmarks). A run that moved nothing has no state to
  // carry: pointing the album at a folder whose contents never arrived would
  // hide the entries still sitting in the old one.
  if (scope.entryCount > 0 && !movedAny) return true;

  await source.applyStoredAlbumRename(filter.album, plan.destination);

  // The rename guard keeps this path to albums whose whole folder the view
  // shows, so what moved is everything the folder held; the strict emptiness
  // check below still covers a merge into a non-empty destination.
  await storageService.deleteEmptyRegularDirectories({filter.album});
  // The database holds the renamed rows now: reload the summaries so the album
  // list and its counts stop showing the album under its old name.
  await reloadPagedSummaries();
  return true;
}
