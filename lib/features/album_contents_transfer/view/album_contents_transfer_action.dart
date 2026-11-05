import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/album_contents_transfer/model/album_contents_transfer_plan.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_entry_feed.dart';
import 'package:aves/features/album_contents_transfer/services/album_contents_scope.dart';
import 'package:aves/features/album_contents_transfer/services/empty_album_folder_cleaner.dart';
import 'package:aves/features/album_contents_transfer/view/album_contents_transfer_dialog.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/model/covers.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/basic/popup/menu_row.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/album_set.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The two ways the album action can treat the contents: take them away or
/// duplicate them.
const _transferModes = [MoveType.move, MoveType.copy];

/// A menu entry carries everything it needs, because the app bar only hands
/// back its opaque value after the menu closes.
class _AlbumContentsTransferCommand {
  final Set<StoredAlbumFilter> albums;
  final Selection<FilterGridItem<AlbumBaseFilter>> selection;
  final AlbumChipSetActionDelegate delegate;
  final MoveType moveType;

  const new({
    required this.albums,
    required this.selection,
    required this.delegate,
    required this.moveType,
  });
}

/// TV has no overflow menu, so selection actions stay reachable as icons.
List<Widget> buildAlbumContentsTransferActions(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
  AlbumChipSetActionDelegate delegate,
) {
  if (!settings.useTvLayout) return const [];
  if (!_canTransfer(context, appMode, selection)) return const [];
  return [
    for (final moveType in _transferModes)
      IconButton(
        icon: Icon(moveType == MoveType.copy ? AIcons.copy : AIcons.move),
        tooltip: _actionLabel(context, moveType),
        onPressed: () => unawaited(
          _start(
            context: context,
            moveType: moveType,
            albums: _selectedAlbums(selection),
            selection: selection,
            delegate: delegate,
          ),
        ),
      ),
  ];
}

/// The phone app bar has one overflow menu; the album actions join it instead
/// of adding another button to the selection bar.
List<PopupMenuEntry<Object>> buildAlbumContentsTransferMenuEntries(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
  AlbumChipSetActionDelegate delegate,
) {
  if (settings.useTvLayout) return const [];
  if (!_canTransfer(context, appMode, selection)) return const [];
  return [
    for (final moveType in _transferModes)
      PopupMenuItem<Object>(
        value: _AlbumContentsTransferCommand(
          albums: _selectedAlbums(selection),
          selection: selection,
          delegate: delegate,
          moveType: moveType,
        ),
        child: MenuRow(
          text: _actionLabel(context, moveType),
          icon: Icon(moveType == MoveType.copy ? AIcons.copy : AIcons.move),
        ),
      ),
  ];
}

Future<void> handleAlbumContentsTransferMenuSelection(BuildContext context, Object value) async {
  if (value is! _AlbumContentsTransferCommand) return;
  await _start(
    context: context,
    moveType: value.moveType,
    albums: value.albums,
    selection: value.selection,
    delegate: value.delegate,
  );
}

/// Moves what the view shows of one album into another, without the album grid
/// behind it.
///
/// The rename guard offers this when the album's folder holds items outside the
/// current view: a move is defined over the visible set, so it cannot take
/// anything the user was not looking at.
Future<void> moveAlbumContentsToAnotherAlbum(
  BuildContext context,
  StoredAlbumFilter filter, {
  required AlbumChipSetActionDelegate delegate,
}) async {
  await _start(
    context: context,
    moveType: MoveType.move,
    albums: {filter},
    // No grid selection to return to: the caller decides where to go next.
    selection: null,
    delegate: delegate,
  );
}

String _actionLabel(BuildContext context, MoveType moveType) {
  return moveType == MoveType.copy ? context.l10n.albumContentsCopyAction : context.l10n.albumContentsMoveAction;
}

bool _canTransfer(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
) {
  if (appMode != AppMode.main || !selection.isSelecting || settings.isReadOnly) return false;
  if (!(CollectionViewHooksScope.maybeOf(context)?.allowFilterMutation ?? true)) return false;
  // A locked visible range freezes library edits, and the lock's `move`
  // permission is the one that covers relocating contents, for a copy as well.
  if (!VisibleRangeGate.allows(VisibleRangeMutation.move)) return false;

  final filters = selection.selectedItems.map((item) => item.filter).toSet();
  final albums = filters.whereType<StoredAlbumFilter>().toSet();
  if (albums.isEmpty || albums.length != filters.length) return false;
  // Taking contents out of a vault would expose it, and a volume root is not
  // an album that can be emptied or removed. A copy out of a vault would expose
  // it just the same, so the rule holds for both modes.
  return albums.every((filter) => !filter.isVault && filter.canRename);
}

Set<StoredAlbumFilter> _selectedAlbums(Selection<FilterGridItem<AlbumBaseFilter>> selection) {
  return selection.selectedItems.map((item) => item.filter).whereType<StoredAlbumFilter>().toSet();
}

/// Moves or copies the visible contents of the selected albums into one
/// destination.
///
/// Two paths, because the targets live in one of two very different places. A
/// library small enough to load keeps the legacy behaviour: the entries come
/// from the in-memory source. A windowed library cannot be materialized, so the
/// same scope is resolved as a database predicate, counted per album for the
/// preview, and walked in bounded batches while the transfer runs — the album
/// grid itself never holds the entries.
Future<void> _start({
  required BuildContext context,
  required MoveType moveType,
  required Set<StoredAlbumFilter> albums,
  required Selection<FilterGridItem<AlbumBaseFilter>>? selection,
  required AlbumChipSetActionDelegate delegate,
}) async {
  if (albums.isEmpty) return;

  final copy = moveType == MoveType.copy;
  final source = context.read<CollectionSource>();
  final albumPaths = albums.map((filter) => filter.album).toSet();
  // Only visible entries travel. Anything outside the visible range stays in
  // its folder, which then cannot pass the strict emptiness check. A copy
  // leaves every source folder in place, so it offers no removal at all.
  final removableAlbumPaths = copy ? const <String>{} : _removableAlbumPaths(albums);

  // A source that holds its entries answers from them; a windowed one keeps them
  // in the database only. `allowFullLoad` alone would take the in-memory path
  // over an entry-free source, so both signals decide together.
  final fullLoad = !await albumActionUsesDatabase(context);
  if (!context.mounted) return;

  final Set<AvesEntry>? inMemoryEntries;
  final AlbumContentsScope? scope;
  final Map<String, int> entryCountByAlbum;
  if (fullLoad) {
    inMemoryEntries = source.visibleEntries.where((entry) => albumPaths.contains(entry.directory)).toSet();
    scope = null;
    entryCountByAlbum = {for (final album in albumPaths) album: 0};
    for (final entry in inMemoryEntries) {
      final directory = entry.directory;
      if (directory == null) continue;
      entryCountByAlbum[directory] = (entryCountByAlbum[directory] ?? 0) + 1;
    }
  } else {
    inMemoryEntries = null;
    scope = await AlbumContentsScope.resolve(albums);
    if (!context.mounted) return;
    if (scope == null) {
      // The scope itself needs the in-memory path, and the library holds too
      // many entries to load: say so instead of moving nothing.
      await pagedScopeUnsupported(context);
      return;
    }
    entryCountByAlbum = scope.countByAlbum;
  }

  if (entryCountByAlbum.values.every((count) => count == 0)) {
    delegate.showFeedback(
      context,
      FeedbackType.info,
      copy ? context.l10n.albumContentsCopyEmpty : context.l10n.albumContentsMoveEmpty,
    );
    return;
  }

  final answer = await showAlbumContentsTransferDialog(
    context: context,
    source: source,
    albums: albums,
    entryCountByAlbum: entryCountByAlbum,
    removableAlbumPaths: removableAlbumPaths,
    moveType: moveType,
  );
  if (answer == null || !context.mounted) return;

  final destination = answer.destination;
  final plan = AlbumContentsTransferPlan.resolve(
    moveType: moveType,
    sourceAlbums: albumPaths,
    destination: destination,
    // The destination album keeps its own entries: picking a selected album as
    // the destination merges the others into it.
    entryCount: entryCountByAlbum.values.fold(0, (sum, count) => sum + count) - (entryCountByAlbum[destination] ?? 0),
  );
  if (!plan.isValid) {
    delegate.showFeedback(context, FeedbackType.warn, context.l10n.albumContentsMoveInvalidDestination);
    return;
  }

  settings.recentDestinationAlbums = settings.recentDestinationAlbums
    ..remove(destination)
    ..insert(0, destination);

  // A copy writes every byte again, while the batched free-space check only
  // sees the current batch. Ask once, from the scope's totals, so the user
  // learns before the first file instead of halfway through.
  if (copy && scope != null) {
    final needed = scope.sizeBytes - scope.sizeIn(destination);
    if (!await delegate.checkFreeSpace(context, needed, destination)) return;
    if (!context.mounted) return;
  }

  final transferredAlbums = <String>{};
  if (inMemoryEntries != null) {
    final entries = inMemoryEntries.where((entry) => entry.directory != destination).toSet();
    transferredAlbums.addAll(entries.map((entry) => entry.directory).nonNulls);
    final completed = await delegate.doQuickMove(
      context,
      moveType: moveType,
      entriesByDestination: {destination: entries},
      cleanupEmptySourceDirectories: false,
    );
    if (!context.mounted || !completed) return;
    selection?.browse();
  } else {
    final transferAlbums = albums.where((filter) => plan.movingAlbums.contains(filter.album)).toSet();
    final predicate = AlbumContentsScope.predicateFor(transferAlbums);
    if (predicate == null) {
      delegate.showFeedback(context, FeedbackType.warn, context.l10n.albumContentsMoveInvalidDestination);
      return;
    }
    final feed = AlbumContentsEntryFeed(
      albums: transferAlbums,
      predicate: predicate,
      count: plan.entryCount,
    );
    final summary = await runOverEntryFeed(
      context,
      feed,
      () async {
        final run = EntryFeedRun.current;
        if (run == null) return;
        final batch = {for (final entry in run.batch) if (entry.directory != null && entry.directory != destination) entry};
        if (batch.isEmpty) return;
        transferredAlbums.addAll(batch.map((entry) => entry.directory).nonNulls);
        final completed = await delegate.doQuickMove(
          context,
          moveType: moveType,
          entriesByDestination: {destination: batch},
          cleanupEmptySourceDirectories: false,
        );
        // A refused batch would fail identically on the next one: stop the run
        // instead of asking for the same permission once per batch.
        if (!completed) run.cancel();
      },
    );
    if (!context.mounted) return;
    if (summary != null) {
      delegate.showFeedback(context, summary.type, summary.message, summary.action);
    }
    selection?.browse();
  }

  if (!copy && answer.deleteEmptyFolders) {
    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: transferredAlbums,
      removableSourceAlbums: removableAlbumPaths,
    );
    if (candidates.isNotEmpty) {
      await const EmptyAlbumFolderCleaner().clean(candidates);
    }
  }

  if (scope != null) {
    // The database holds the transferred rows now. A windowed library answers
    // the album list and its counts from the summaries, which reload only on a
    // lens resolve: without this the album page keeps showing the pre-transfer
    // counts (and an emptied album) until the user re-enters the collection.
    await reloadPagedSummaries();
  }
}

Set<String> _removableAlbumPaths(Iterable<StoredAlbumFilter> albums) {
  final pinned = settings.pinnedFilters.whereType<StoredAlbumFilter>().map((filter) => filter.album).toSet();
  return albums.where((filter) {
    if (filter.isVault || pinned.contains(filter.album) || !filter.canRename) return false;
    // Special albums (camera, download, screenshots, app) and vaults stay on
    // disk even when they end up empty: only ordinary albums are removable.
    return covers.effectiveAlbumType(filter.album) == AlbumType.regular;
  }).map((filter) => filter.album).toSet();
}
