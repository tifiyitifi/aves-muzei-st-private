import 'package:aves/features/album_contents_transfer/services/album_contents_entry_feed.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_scope.dart';
import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Deletes the visible contents of the selected albums from the database.
///
/// The album grid renders summaries, not entries, so a library too large to
/// load gives the action no entry list. The scope is resolved as the very
/// predicate the album tiles count (visible range, hidden filters and locked
/// vaults included), then walked in bounded batches, so only the entries the
/// user can see are deleted and everything outside the range stays in place.
///
/// Answers false when the caller must keep its in-memory path: the library is
/// small enough to load, so the legacy code owns the exact same decision.
///
/// [filters] must already be unlocked; the caller owns the vault unlock step.
Future<bool> deleteAlbumContentsFromDatabase(
  BuildContext context, {
  required Set<StoredAlbumFilter> filters,
  required bool enableBin,
}) async {
  if (filters.isEmpty) return true;
  if (await const CollectionEngineRouter().allowFullLoad()) return false;

  final scope = await AlbumContentsScope.resolve(filters);
  if (!context.mounted) return true;
  if (scope == null) {
    // The scope needs the in-memory path, and the library holds too many
    // entries to load: say so instead of deleting nothing.
    await pagedScopeUnsupported(context);
    return true;
  }

  final albums = filters.map((filter) => filter.album).toSet();
  final source = context.read<CollectionSource>();
  final delegate = EntrySetActionDelegate();
  final l10n = context.l10n;

  if (scope.entryCount > 0) {
    final feed = AlbumContentsEntryFeed(albums: filters, predicate: scope.predicate, count: scope.entryCount);
    if (enableBin) {
      final summary = await runOverEntryFeed(context, feed, () async {
        final run = EntryFeedRun.current;
        final batch = run?.batch;
        if (run == null || batch == null || batch.isEmpty) return;
        // The bin confirmation is asked by `doMove`, once per run.
        final completed = await delegate.doMove(context, moveType: MoveType.toBin, entries: batch.toSet());
        // A refused batch would fail identically on the next one: stop the run
        // instead of asking for the same permission once per batch.
        if (!completed) run.cancel();
      });
      if (context.mounted && summary != null) {
        delegate.showFeedback(context, summary.type, summary.message, summary.action);
      }
    } else {
      if (!await showConfirmationDialog(
        context: context,
        message: filters.length == 1 ? l10n.deleteSingleAlbumConfirmationDialogMessage(scope.entryCount) : l10n.deleteMultiAlbumConfirmationDialogMessage(scope.entryCount),
        ok: l10n.deleteButtonLabel,
      )) {
        return true;
      }
      if (!context.mounted) return true;

      // The album confirmation above is the one the user answered, so the
      // generic delete-forever dialog is not asked again for every batch.
      settings.pinnedFilters = settings.pinnedFilters..removeAll(filters);
      final summary = await runOverEntryFeed(context, feed, () async {
        final run = EntryFeedRun.current;
        final batch = run?.batch;
        if (run == null || batch == null || batch.isEmpty) return;
        final completed = await delegate.doDelete(context: context, entries: batch.toSet(), enableBin: false, confirm: false);
        if (!completed) run.cancel();
      });
      if (context.mounted && summary != null) {
        delegate.showFeedback(context, summary.type, summary.message, summary.action);
      }
    }
  }

  if (!context.mounted) return true;
  source.forgetNewAlbums(albums);
  source.cleanEmptyAlbums(albums);
  if (!enableBin) {
    // A vault is removed only once its album is provably empty. A windowed
    // source holds no entries to ask, so count the rows that remain instead.
    final vaultAlbums = filters.where((filter) => vaults.isVault(filter.album)).toSet();
    if (vaultAlbums.isNotEmpty) {
      final remaining = await AlbumContentsScope.resolve(vaultAlbums);
      if (remaining != null) {
        final emptyVaultAlbums = vaultAlbums.where((filter) => remaining.countIn(filter.album) == 0).map((filter) => filter.album).toSet();
        await vaults.remove(emptyVaultAlbums);
      }
    }
  }
  return true;
}
