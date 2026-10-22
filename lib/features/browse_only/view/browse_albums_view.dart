import 'dart:async';

import 'package:aves/features/browse_only/services/browse_album_loader.dart';
import 'package:aves/features/browse_only/services/browse_albums.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_media_grid.dart';
import 'package:aves/features/browse_only/view/browse_sort_button.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/browse_only_notice_bar.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/theme.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/thumbnail/decorated.dart';
import 'package:material_ui/material_ui.dart';

/// The album grid of the browse-only surface.
///
/// The list, the covers and the counts come from one aggregate read of the media
/// store, so a count is never seen growing and a folder is complete even while
/// the timeline is only a preview of the newest rows. An album's *contents* are
/// read when it is opened (see `BrowseAlbumLoader`).
class BrowseAlbumsView extends StatefulWidget {
  const new({super.key});

  @override
  State<BrowseAlbumsView> createState() => _BrowseAlbumsViewState();
}

class _BrowseAlbumsViewState extends State<BrowseAlbumsView> {
  @override
  void initState() {
    super.initState();
    unawaited(browseAlbums.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([browseAlbums, browsePrefs]),
      builder: (context, child) {
        final albums = browseAlbums.albumsSorted(sort: browsePrefs.albumSort, reverse: browsePrefs.albumReverse);
        if (albums.isEmpty) {
          return EmptyContent(
            icon: AIcons.album,
            text: libraryPhase.isBrowsing && pagedImportStatus.active ? context.l10n.sourceStateImporting : context.l10n.albumEmpty,
          );
        }
        return GridTheme(
          extent: 120,
          child: GridView.builder(
            primary: false,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: .74,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) => _BrowseAlbumTile(album: albums[index]),
          ),
        );
      },
    );
  }
}

class _BrowseAlbumTile extends StatelessWidget {
  final BrowseAlbum album;

  const new({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.maybeOf(context)?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: BrowseAlbumPage.routeName),
          builder: (context) => BrowseAlbumPage(album: album),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final extent = constraints.biggest.shortestSide;
                  return Center(
                    child: DecoratedThumbnail(
                      entry: album.cover,
                      tileExtent: extent,
                      selectable: false,
                      highlightable: false,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            context.l10n.browseOnlyAlbumCount(album.count),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The album list as its own page, for the drawer's album entry while the
/// browser is the collection surface.
class BrowseOnlyAlbumsPage extends StatelessWidget {
  static const routeName = '/browse-only/albums';

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    // The strip belongs to the phase, not to this page: the handoff can happen
    // while the page is still on screen, and a bar written in once would keep
    // claiming the library is being organized.
    return ListenableBuilder(
      listenable: Listenable.merge([libraryPhase, pagedImportStatus]),
      builder: (context, child) => AvesScaffold(
        appBar: AppBar(
          title: Text(context.l10n.browseOnlyAlbumsTab),
          actions: const [BrowseAlbumSortButton()],
          bottom: browseOnlyNoticeBar(),
        ),
        body: const BrowseAlbumsView(),
      ),
    );
  }
}

/// One album's media, pushed from the album grid.
///
/// The rows are read from the media store for this directory alone, the way the
/// album list itself is read: a page paints immediately, the folder's remaining
/// rows follow, and the count in the app bar is the whole one the album grid
/// showed.
class BrowseAlbumPage extends StatefulWidget {
  static const routeName = '/browse-only/album';

  final BrowseAlbum album;

  const new({super.key, required this.album});

  @override
  State<BrowseAlbumPage> createState() => _BrowseAlbumPageState();
}

class _BrowseAlbumPageState extends State<BrowseAlbumPage> {
  late final BrowseAlbumLoader _loader;

  @override
  void initState() {
    super.initState();
    _loader = BrowseAlbumLoader(directory: widget.album.directory);
    unawaited(_loader.load());
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = _loader.library;
    return ListenableBuilder(
      listenable: Listenable.merge([browsePrefs, library, libraryPhase, pagedImportStatus]),
      builder: (context, child) {
        final sort = browsePrefs.mediaSort;
        final indexes = library.mediaIndexes(sort: sort, reverse: browsePrefs.mediaReverse);
        return AvesScaffold(
          appBar: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.album.name),
                Text(
                  context.l10n.browseOnlyAlbumCount(widget.album.count),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: const [BrowseMediaSortButton()],
            bottom: browseOnlyNoticeBar(),
          ),
          // A read still in flight is not an empty album: say so instead of
          // showing "no media" for the moment the directory query takes.
          body: indexes.isEmpty && library.loading
              ? const Center(child: CircularProgressIndicator())
              : BrowseMediaGrid(
                  library: library,
                  indexes: indexes,
                  sectioned: sort == BrowseMediaSort.date,
                  emptyText: context.l10n.albumEmpty,
                ),
        );
      },
    );
  }
}
