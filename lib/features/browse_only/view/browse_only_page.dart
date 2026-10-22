import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_albums_view.dart';
import 'package:aves/features/browse_only/view/browse_bottom_bar.dart';
import 'package:aves/features/browse_only/view/browse_media_grid.dart';
import 'package:aves/features/browse_only/view/browse_sort_button.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/view/browse_only_notice_bar.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The browsing surface used until the collection can serve the library.
///
/// It reads the media store directly (through [browseLibrary]), so it is whole
/// from the first scan and knows nothing about how far the import has got:
/// switching views, opening an album or coming back can never show zero rows
/// because a database was still being written. Editing stays out of it, which
/// is also what makes it safe while the background passes read every file.
///
/// It is deliberately a separate surface, not the collection with filters
/// applied: the collection's own views answer from catalogued data, and every
/// attempt to make them answer earlier leaked half-built answers into the UI.
class BrowseOnlyPage extends StatefulWidget {
  static const routeName = '/browse-only';

  const new({super.key});

  @override
  State<BrowseOnlyPage> createState() => _BrowseOnlyPageState();
}

class _BrowseOnlyPageState extends State<BrowseOnlyPage> {
  BrowseView _view = BrowseView.timeline;

  @override
  void initState() {
    super.initState();
    // The window reads its first page straight from the media store instead of
    // waiting for the import's row stream: the import is only as fast as the
    // database writes, so a browsing surface fed by it would grow one row at a
    // time.
    unawaited(browseLibrary.loadFirstPage());
    unawaited(browsePrefs.init());
  }

  @override
  void dispose() {
    // The browser retires with the wait it covered. Once the phase is ready
    // nothing can navigate back here, so the window can go immediately; while
    // the wait is still on, the rows stay for the page that comes back to them.
    if (libraryPhase.isReady) browseLibrary.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The collection page owns the drawer (settings, bin, ...): open that one
    // instead of nesting a second drawer-less scaffold.
    final outerScaffold = Scaffold.maybeOf(context);
    return AvesScaffold(
      appBar: AppBar(
        leading: outerScaffold != null && outerScaffold.hasDrawer
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                icon: const Icon(Icons.menu),
                onPressed: outerScaffold.openDrawer,
              )
            : null,
        title: Text(_title(context)),
        actions: [
          if (_view == BrowseView.albums) const BrowseAlbumSortButton() else const BrowseMediaSortButton(),
        ],
        // The import counter is status, not the notice the setting hides. A
        // cold-start wait (a complete library, a slow resolve) shows the
        // browser too, but has nothing to explain: the bar belongs to the
        // organized-library-free window, not to a spinner.
        bottom: browseOnlyNoticeBar(),
      ),
      body: _buildBody(context),
      bottomNavigationBar: BrowseOnlyBottomBar(
        view: _view,
        onSelect: (view) {
          if (view == _view) return;
          setState(() => _view = view);
        },
      ),
    );
  }

  String _title(BuildContext context) => switch (_view) {
    BrowseView.timeline => context.l10n.browseOnlyTimelineTab,
    BrowseView.albums => context.l10n.browseOnlyAlbumsTab,
  };

  Widget _buildBody(BuildContext context) {
    switch (_view) {
      case BrowseView.albums:
        return const BrowseAlbumsView();
      case BrowseView.timeline:
        return _buildTimeline(context);
    }
  }

  Widget _buildTimeline(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([browsePrefs, browseLibrary]),
      builder: (context, child) {
        final sort = browsePrefs.mediaSort;
        final grid = BrowseMediaGrid(
          library: browseLibrary,
          key: const PageStorageKey('browse-timeline'),
          indexes: browseLibrary.mediaIndexes(sort: sort, reverse: browsePrefs.mediaReverse),
          sectioned: sort == BrowseMediaSort.date,
        );
        if (!_showTimelineFooter) return grid;
        // The timeline is a preview of the newest rows: the album list is whole
        // and the collection takes over with the full timeline, so say where the
        // rest is instead of letting the end of the grid read as the end of the
        // library.
        return Column(
          children: [
            Expanded(child: grid),
            const _BrowseTimelinePreview(),
          ],
        );
      },
    );
  }

  /// Whether the timeline footer has something to say: the window stopped at its
  /// own limit, or the last page failed and the rest of the rows are still out
  /// there.
  bool get _showTimelineFooter => browseLibrary.atLimit || browseLibrary.error != null;
}

/// The strip under a timeline that is a preview, pointing at the whole album
/// list and offering the rows the preview stopped short of.
class _BrowseTimelinePreview extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
        child: Row(
          children: [
            Icon(AIcons.image, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.browseOnlyTimelinePreview(browseLibrary.length),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                // The strip is one line high: a default-sized button would
                // overflow it.
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
              ),
              onPressed: browseLibrary.error != null ? () => unawaited(browseLibrary.retry()) : () => unawaited(browseLibrary.loadMore(beyondPreviewLimit: true)),
              child: Text(context.l10n.browseOnlyTimelineContinue),
            ),
          ],
        ),
      ),
    );
  }
}
