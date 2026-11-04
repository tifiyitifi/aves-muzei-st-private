import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/album_contents_move/model/album_contents_move_plan.dart';
import 'package:aves/features/album_contents_move/services/album_contents_entry_feed.dart';
import 'package:aves/features/album_contents_move/services/album_contents_scope.dart';
import 'package:aves/features/album_contents_move/services/empty_album_folder_cleaner.dart';
import 'package:aves/features/album_contents_move/view/album_contents_move_dialog.dart';
import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/features/collection_paging/selection/entry_feed_run.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
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

/// A menu entry carries everything it needs, because the app bar only hands
/// back its opaque value after the menu closes.
class _AlbumContentsMoveCommand {
  final Set<StoredAlbumFilter> albums;
  final Selection<FilterGridItem<AlbumBaseFilter>> selection;
  final AlbumChipSetActionDelegate delegate;

  const new({
    required this.albums,
    required this.selection,
    required this.delegate,
  });
}

/// TV has no overflow menu, so selection actions stay reachable as icons.
List<Widget> buildAlbumContentsMoveActions(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
  AlbumChipSetActionDelegate delegate,
) {
  if (!settings.useTvLayout) return const [];
  if (!_canMove(context, appMode, selection)) return const [];
  return [
    IconButton(
      icon: const Icon(AIcons.move),
      tooltip: context.l10n.albumContentsMoveAction,
      onPressed: () => unawaited(
        _start(
          context: context,
          albums: _selectedAlbums(selection),
          selection: selection,
          delegate: delegate,
        ),
      ),
    ),
  ];
}

/// The phone app bar has one overflow menu; the album action joins it instead
/// of adding another button to the selection bar.
List<PopupMenuEntry<Object>> buildAlbumContentsMoveMenuEntries(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
  AlbumChipSetActionDelegate delegate,
) {
  if (settings.useTvLayout) return const [];
  if (!_canMove(context, appMode, selection)) return const [];
  return [
    PopupMenuItem<Object>(
      value: _AlbumContentsMoveCommand(
        albums: _selectedAlbums(selection),
        selection: selection,
        delegate: delegate,
      ),
      child: MenuRow(
        text: context.l10n.albumContentsMoveAction,
        icon: const Icon(AIcons.move),
      ),
    ),
  ];
}

Future<void> handleAlbumContentsMoveMenuSelection(BuildContext context, Object value) async {
  if (value is! _AlbumContentsMoveCommand) return;
  await _start(
    context: context,
    albums: value.albums,
    selection: value.selection,
    delegate: value.delegate,
  );
}

bool _canMove(
  BuildContext context,
  AppMode appMode,
  Selection<FilterGridItem<AlbumBaseFilter>> selection,
) {
  if (appMode != AppMode.main || !selection.isSelecting || settings.isReadOnly) return false;
  if (!(CollectionViewHooksScope.maybeOf(context)?.allowFilterMutation ?? true)) return false;

  final filters = selection.selectedItems.map((item) => item.filter).toSet();
  final albums = filters.whereType<StoredAlbumFilter>().toSet();
  if (albums.isEmpty || albums.length != filters.length) return false;
  // Moving out of a vault would expose its content, and a volume root is not
  // an album that can be emptied or removed.
  return albums.every((filter) => !filter.isVault && filter.canRename);
}

Set<StoredAlbumFilter> _selectedAlbums(Selection<FilterGridItem<AlbumBaseFilter>> selection) {
  return selection.selectedItems.map((item) => item.filter).whereType<StoredAlbumFilter>().toSet();
}

/// Moves the visible contents of the selected albums into one destination.
///
/// Two paths, because the targets live in one of two very different places. A
/// library small enough to load keeps the legacy behaviour: the entries come
/// from the in-memory source. A windowed library cannot be materialized, so the
/// same scope is resolved as a database predicate, counted per album for the
/// preview, and walked in bounded batches while the move runs — the album grid
/// itself never holds the entries.
Future<void> _start({
  required BuildContext context,
  required Set<StoredAlbumFilter> albums,
  required Selection<FilterGridItem<AlbumBaseFilter>> selection,
  required AlbumChipSetActionDelegate delegate,
}) async {
  if (albums.isEmpty) return;

  final source = context.read<CollectionSource>();
  final albumPaths = albums.map((filter) => filter.album).toSet();
  // Only visible entries travel. Anything outside the visible range stays in
  // its folder, which then cannot pass the strict emptiness check.
  final removableAlbumPaths = _removableAlbumPaths(albums);

  final fullLoad = await const CollectionEngineRouter().allowFullLoad();
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
    delegate.showFeedback(context, FeedbackType.info, context.l10n.albumContentsMoveEmpty);
    return;
  }

  final answer = await showAlbumContentsMoveDialog(
    context: context,
    source: source,
    albums: albums,
    entryCountByAlbum: entryCountByAlbum,
    removableAlbumPaths: removableAlbumPaths,
  );
  if (answer == null || !context.mounted) return;

  final destination = answer.destination;
  final plan = AlbumContentsMovePlan.resolve(
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

  final movedAlbums = <String>{};
  if (inMemoryEntries != null) {
    final entries = inMemoryEntries.where((entry) => entry.directory != destination).toSet();
    movedAlbums.addAll(entries.map((entry) => entry.directory).nonNulls);
    final completed = await delegate.doQuickMove(
      context,
      moveType: MoveType.move,
      entriesByDestination: {destination: entries},
      cleanupEmptySourceDirectories: false,
    );
    if (!context.mounted || !completed) return;
    selection.browse();
  } else {
    final movingAlbums = albums.where((filter) => plan.movingAlbums.contains(filter.album)).toSet();
    final predicate = AlbumContentsScope.predicateFor(movingAlbums);
    if (predicate == null) {
      delegate.showFeedback(context, FeedbackType.warn, context.l10n.albumContentsMoveInvalidDestination);
      return;
    }
    final feed = AlbumContentsEntryFeed(
      albums: movingAlbums,
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
        movedAlbums.addAll(batch.map((entry) => entry.directory).nonNulls);
        final completed = await delegate.doQuickMove(
          context,
          moveType: MoveType.move,
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
    selection.browse();
  }

  if (answer.deleteEmptyFolders) {
    final candidates = plan.cleanupCandidates(
      movedSourceAlbums: movedAlbums,
      removableSourceAlbums: removableAlbumPaths,
    );
    if (candidates.isNotEmpty) {
      await const EmptyAlbumFolderCleaner().clean(candidates);
    }
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
