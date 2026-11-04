import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/album_contents_move/model/album_contents_move_plan.dart';
import 'package:aves/features/album_contents_move/services/empty_album_folder_cleaner.dart';
import 'package:aves/features/album_contents_move/view/album_contents_move_dialog.dart';
import 'package:aves/features/collection_paging/view/collection_view_hooks.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
import 'package:aves/model/covers.dart';
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

Future<void> _start({
  required BuildContext context,
  required Set<StoredAlbumFilter> albums,
  required Selection<FilterGridItem<AlbumBaseFilter>> selection,
  required AlbumChipSetActionDelegate delegate,
}) async {
  if (albums.isEmpty) return;
  if (await pagedScopeUnsupported(context)) return;
  if (!context.mounted) return;

  final source = context.read<CollectionSource>();
  final albumPaths = albums.map((filter) => filter.album).toSet();
  // Only visible entries travel. Anything outside the visible range stays in
  // its folder, which then cannot pass the strict emptiness check.
  final entries = source.visibleEntries.where((entry) => albumPaths.contains(entry.directory)).toSet();
  if (entries.isEmpty) {
    delegate.showFeedback(context, FeedbackType.info, context.l10n.albumContentsMoveEmpty);
    return;
  }

  final removableAlbumPaths = _removableAlbumPaths(albums);
  final answer = await showAlbumContentsMoveDialog(
    context: context,
    source: source,
    albums: albums,
    entries: entries,
    removableAlbumPaths: removableAlbumPaths,
  );
  if (answer == null || !context.mounted) return;

  final plan = AlbumContentsMovePlan.resolve(
    sourceAlbums: albumPaths,
    removableSourceAlbums: removableAlbumPaths,
    destination: answer.destination,
    entries: entries,
  );
  if (!plan.isValid) {
    delegate.showFeedback(context, FeedbackType.warn, context.l10n.albumContentsMoveInvalidDestination);
    return;
  }

  settings.recentDestinationAlbums = settings.recentDestinationAlbums
    ..remove(answer.destination)
    ..insert(0, answer.destination);

  final completed = await delegate.doQuickMove(
    context,
    moveType: MoveType.move,
    entriesByDestination: plan.entriesByDestination,
    cleanupEmptySourceDirectories: false,
  );
  if (!context.mounted || !completed) return;

  selection.browse();
  if (answer.deleteEmptyFolders && plan.sourceAlbumsToClean.isNotEmpty) {
    await const EmptyAlbumFolderCleaner().clean(plan.sourceAlbumsToClean);
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
