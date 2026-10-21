import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_albums_view.dart';
import 'package:aves/features/browse_only/view/browse_bottom_bar.dart';
import 'package:aves/features/browse_only/view/browse_media_grid.dart';
import 'package:aves/features/browse_only/view/browse_sort_button.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/view/browse_only_notice_bar.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

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
    // The index scans on its own instead of waiting for the import's row
    // stream: the import is only as fast as the database writes, so a browsing
    // surface fed by it would grow one album at a time.
    unawaited(browseLibrary.scan());
    unawaited(browsePrefs.init());
  }

  @override
  void dispose() {
    browseLibrary.stopScan();
    // The browser retires with the wait it covered. Once the phase is ready
    // nothing can navigate back here, so the index can go immediately.
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

  String _title(BuildContext context) {
    // The bar keeps the user's own items, so the title follows the item that
    // owns the current view instead of inventing a second set of names.
    final items = context.select<Settings, List<AvesNavItem>>((v) => v.bottomNavigationActions);
    final item = items.firstWhereOrNull((item) => BrowseOnlyBottomBar.viewFor(item) == _view);
    if (item != null) return item.getText(context);
    final l10n = context.l10n;
    return switch (_view) {
      BrowseView.timeline => l10n.browseOnlyTimelineTab,
      BrowseView.albums => l10n.browseOnlyAlbumsTab,
      BrowseView.videos => l10n.browseOnlyVideosTab,
    };
  }

  Widget _buildBody(BuildContext context) {
    switch (_view) {
      case BrowseView.albums:
        return const BrowseAlbumsView();
      case BrowseView.timeline:
        return _buildMedia(context, videosOnly: false, storageKey: 'browse-timeline');
      case BrowseView.videos:
        return _buildMedia(context, videosOnly: true, storageKey: 'browse-videos');
    }
  }

  Widget _buildMedia(BuildContext context, {required bool videosOnly, required String storageKey}) {
    return ListenableBuilder(
      listenable: Listenable.merge([browsePrefs, browseLibrary]),
      builder: (context, child) {
        final sort = browsePrefs.mediaSort;
        return BrowseMediaGrid(
          key: PageStorageKey(storageKey),
          indexes: browseLibrary.mediaIndexes(sort: sort, reverse: browsePrefs.mediaReverse, videosOnly: videosOnly),
          sectioned: sort == BrowseMediaSort.date,
          emptyText: videosOnly ? context.l10n.collectionEmptyVideos : null,
        );
      },
    );
  }
}
