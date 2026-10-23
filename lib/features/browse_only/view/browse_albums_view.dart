import 'dart:async';

import 'package:aves/features/browse_only/services/browse_album_loader.dart';
import 'package:aves/features/browse_only/services/browse_albums.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/browse_only/view/browse_media_grid.dart';
import 'package:aves/features/browse_only/view/browse_sort_button.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/browse_only_notice_bar.dart';
import 'package:aves/model/settings/settings.dart';
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
      listenable: Listenable.merge([browseAlbums, browsePrefs, settings]),
      builder: (context, child) {
        final albums = browseAlbums.albumsSorted(sort: browsePrefs.albumSort, reverse: browsePrefs.albumReverse);
        if (albums.isEmpty) {
          if (browseAlbums.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (browseAlbums.error != null) {
            // A failed read is not an empty library: say so and let the user
            // ask again, instead of claiming there are no folders.
            return EmptyContent(
              icon: AIcons.error,
              text: context.l10n.browseOnlyAlbumsFailed,
              bottom: TextButton(
                onPressed: () => unawaited(browseAlbums.load()),
                child: Text(context.l10n.collectionLoadingRetry),
              ),
            );
          }
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
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .7,
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
      borderRadius: BorderRadius.circular(16),
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
              borderRadius: BorderRadius.circular(16),
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
            _subtitle(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// How much the folder holds, and when its newest item is from.
  ///
  /// The date comes from the same aggregate read as the count, so it costs one
  /// format call per visible tile and no extra media-store query.
  String _subtitle(BuildContext context) {
    final l10n = context.l10n;
    if (album.maxDateMillis <= 0) return l10n.browseOnlyAlbumCount(album.count);
    final date = settings.avesLocale.yMMMd(DateTime.fromMillisecondsSinceEpoch(album.maxDateMillis));
    return l10n.browseOnlyAlbumSummary(album.count, date);
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

  void _retry() => unawaited(_loader.retry());

  @override
  Widget build(BuildContext context) {
    final library = _loader.library;
    return ListenableBuilder(
      listenable: Listenable.merge([browsePrefs, library, libraryPhase, pagedImportStatus, settings]),
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
          body: _buildBody(context, library, indexes, sort),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, BrowseLibrary library, List<int> indexes, BrowseMediaSort sort) {
    final grid = BrowseMediaGrid(
      library: library,
      indexes: indexes,
      sectioned: sort == BrowseMediaSort.date,
      emptyText: context.l10n.albumEmpty,
    );
    if (indexes.isEmpty) {
      // A read still in flight is not an empty album: say so instead of showing
      // "no media" for the moment the directory query takes. A read that failed
      // is not an empty one either: say so and let the user ask again.
      if (library.loading) return const Center(child: CircularProgressIndicator());
      if (library.error != null) {
        return EmptyContent(
          icon: AIcons.error,
          text: context.l10n.browseOnlyAlbumsFailed,
          bottom: TextButton(onPressed: _retry, child: Text(context.l10n.collectionLoadingRetry)),
        );
      }
      return grid;
    }
    return Column(
      children: [
        Expanded(child: grid),
        // The rows already read stay; the failed tail can be asked for again
        // without leaving the folder.
        if (library.error != null) _BrowseReadErrorBar(onRetry: _retry),
      ],
    );
  }
}

/// The strip under an album whose last page failed.
class _BrowseReadErrorBar extends StatelessWidget {
  final VoidCallback onRetry;

  const new({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onErrorContainer;
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
        child: Row(
          children: [
            Icon(AIcons.error, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.browseOnlyAlbumsFailed,
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
              onPressed: onRetry,
              child: Text(context.l10n.collectionLoadingRetry),
            ),
          ],
        ),
      ),
    );
  }
}
