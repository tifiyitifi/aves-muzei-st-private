import 'dart:async';
import 'dart:math';

import 'package:aves/features/browse_only/model/browse_grid_items.dart';
import 'package:aves/features/browse_only/model/browse_scroll_map.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/view/browse_timeline_scroller.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/theme.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/providers/selection_provider.dart';
import 'package:aves/widgets/common/thumbnail/decorated.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The height of a month header, and the gap between tiles.
///
/// A gallery reads as a grid of pictures, not a wall of them: the gap is the
/// smallest one that still separates two neighbours, and it matches the album
/// grid's.
const double _headerExtent = 44;
const double _tileSpacing = 2;
const double _bottomPadding = 16;

/// Builds the tile at a position of the displayed order.
typedef BrowseTileBuilder = Widget Function(BuildContext context, int position);

/// The media grid of the browse-only surface: a timeline of months, or a flat
/// grid when the order is not chronological.
///
/// It renders exactly the rows it is given, in exactly that order. The ordering
/// belongs to the [BrowseLibrary] it is handed (the whole-library timeline, or
/// one album loaded from the media store), so this widget stays a renderer: a
/// sort change is a new list, not a different code path.
class BrowseMediaGrid extends StatefulWidget {
  /// The rows [indexes] point into.
  final BrowseLibrary library;

  /// Row positions in display order.
  final List<int> indexes;

  /// Whether to group the rows into month sections (only meaningful when the
  /// order is chronological).
  final bool sectioned;

  /// Shown when there is nothing to render.
  final String? emptyText;

  /// Builds one tile, by default the browse surface's own thumbnail tile.
  ///
  /// A caller that only cares about the layout (this grid's own tests do) can
  /// pass a cheaper tile instead of standing up the image pipeline.
  final BrowseTileBuilder? tileBuilder;

  const new({
    super.key,
    required this.library,
    required this.indexes,
    this.sectioned = true,
    this.emptyText,
    this.tileBuilder,
  });

  @override
  State<BrowseMediaGrid> createState() => _BrowseMediaGridState();
}

/// The header above a month's rows.
///
/// It is an ordinary item of the list, not a pinned sliver (see
/// [browseGridItems] for why).
class BrowseMonthHeader extends StatelessWidget {
  final int year, month;

  const new({super.key, required this.year, required this.month});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: _headerExtent,
      color: theme.colorScheme.surface,
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
      alignment: AlignmentDirectional.bottomStart,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          settings.avesLocale.yMMMM(DateTime(year, month)),
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _BrowseMediaGridState extends State<BrowseMediaGrid> {
  /// How close to the end of the grid the next page is asked for: about two
  /// screens, so the rows are there before the user reaches them.
  static const double _pagingThreshold = 1200;

  List<BrowseGridItem>? _items;
  List<int>? _itemsFor;
  int _itemsColumns = 0;

  /// The scrollbar's month starts, cached on the same key as [_items] plus the
  /// tile size (a row's height follows from it).
  BrowseScrollMap? _scrollMap;
  List<BrowseGridItem>? _scrollMapFor;
  double _scrollMapRowExtent = 0;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, child) {
        if (widget.indexes.isEmpty) return _buildEmpty(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final extent = _tileExtent(constraints.maxWidth);
            final columns = (constraints.maxWidth / extent).round().clamp(2, 12);
            // Tiles share a row exactly, so the last column reaches the edge at
            // every column count instead of leaving the remainder to chance.
            final tileExtent = (constraints.maxWidth - (columns - 1) * _tileSpacing) / columns;
            return GridTheme(
              extent: tileExtent,
              child: _withPaging(
                widget.sectioned ? _buildSectionedGrid(context, columns, tileExtent) : _buildFlatGrid(context, columns, tileExtent),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) => EmptyContent(
    icon: AIcons.image,
    // A view with no rows can read as "nothing here" or as "not imported yet":
    // while the library is still being organized the second is the truth, even
    // for a narrowed view (videos) that has a text of its own.
    text: libraryPhase.isBrowsing && pagedImportStatus.active ? context.l10n.sourceStateImporting : widget.emptyText ?? context.l10n.browseOnlyEmptyLibrary,
  );

  /// The sectioned grid is one list: a month header, then the rows of tiles
  /// under it, then the next month.
  ///
  /// One sliver, not one sliver per section: the sections are consecutive rows
  /// of the same order, so a single list is also the cheaper way to lay them
  /// out (a grid per section builds the beginning of each one offscreen, cf.
  /// `SectionedListSliver`).
  Widget _buildSectionedGrid(BuildContext context, int columns, double tileExtent) {
    // The items are derived from the same list instance the library returns for
    // a given order, so identity is a safe cache key.
    if (!identical(_itemsFor, widget.indexes) || _itemsColumns != columns) {
      _items = browseGridItems(widget.library, widget.indexes, columns: columns);
      _itemsFor = widget.indexes;
      _itemsColumns = columns;
    }
    final items = _items!;
    final scrollView = CustomScrollView(
      primary: false,
      controller: _scrollController,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => switch (items[index]) {
              BrowseMonthItem(:final year, :final month) => BrowseMonthHeader(year: year, month: month),
              BrowseRowItem(:final start, :final count) => _buildRow(context, tileExtent, start, count),
            },
            childCount: items.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _bottomPadding)),
      ],
    );
    final scrollMap = _scrollMapOf(items, tileExtent);
    if (!BrowseTimelineScroller.appliesTo(scrollMap)) return scrollView;
    return BrowseTimelineScroller(
      controller: _scrollController,
      map: scrollMap,
      child: scrollView,
    );
  }

  /// The month starts of the list being rendered, cached until the items or the
  /// tile size change.
  BrowseScrollMap _scrollMapOf(List<BrowseGridItem> items, double tileExtent) {
    final rowExtent = tileExtent + _tileSpacing;
    if (!identical(_scrollMapFor, items) || _scrollMapRowExtent != rowExtent) {
      _scrollMap = BrowseScrollMap.of(
        items,
        headerExtent: _headerExtent,
        rowExtent: rowExtent,
        bottomPadding: _bottomPadding,
      );
      _scrollMapFor = items;
      _scrollMapRowExtent = rowExtent;
    }
    return _scrollMap!;
  }

  /// One row of tiles.
  ///
  /// The tiles are sized explicitly rather than spread over the row, so a short
  /// last row keeps the size of the rows above it instead of stretching. The
  /// slots are flexible so a row can never overflow by a rounding error.
  Widget _buildRow(BuildContext context, double tileExtent, int start, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _tileSpacing),
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: _tileSpacing),
            Flexible(
              child: SizedBox(
                width: tileExtent,
                height: tileExtent,
                child: _buildTile(context, start + i),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlatGrid(BuildContext context, int columns, double tileExtent) {
    return GridView.builder(
      primary: false,
      padding: const EdgeInsets.only(bottom: _bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: _tileSpacing,
        crossAxisSpacing: _tileSpacing,
      ),
      itemCount: widget.indexes.length,
      itemBuilder: _buildTile,
    );
  }

  Widget _buildTile(BuildContext context, int position) =>
      widget.tileBuilder?.call(context, position) ??
      _BrowseTile(
        library: widget.library,
        order: widget.indexes,
        position: position,
      );

  /// Asks for the next page when the grid comes near its end.
  ///
  /// The window owns the loading state, so a scroll that fires on every frame
  /// still reads one page at a time, and a window that stopped (at the end of
  /// the library, or at its own preview limit) ignores the request entirely.
  Widget _withPaging(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < _pagingThreshold) {
          unawaited(widget.library.loadMore());
        }
        return false;
      },
      child: child,
    );
  }

  /// The tile size the collection grid would use, so both surfaces read the
  /// same way. Falls back to four columns on a phone.
  static double _tileExtent(double width) {
    final configured = settings.getTileExtent(CollectionPage.routeName);
    return configured > 0 ? configured : width / 4;
  }
}

class _BrowseTile extends StatelessWidget {
  /// The store the row indexes point into.
  final BrowseLibrary library;

  /// The displayed order, so the viewer opens on the same sequence the grid
  /// shows and swiping follows the sort.
  final List<int> order;
  final int position;

  const new({
    required this.library,
    required this.order,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final index = order[position];
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openBrowseOnlyViewer(context, library, order, position),
        child: DecoratedThumbnail(
          entry: library.entryAt(index),
          tileExtent: constraints.maxWidth,
          selectable: false,
          highlightable: false,
        ),
      ),
    );
  }
}

/// Opens the viewer on a window around [position] of the displayed order.
///
/// The viewer gets a bounded selection instead of the whole index: a selection
/// of 30,000 rows would materialize exactly the library the index exists to
/// keep compact, and swiping stays useful across a few hundred neighbours.
void openBrowseOnlyViewer(BuildContext context, BrowseLibrary library, List<int> order, int position) {
  if (position < 0 || position >= order.length) return;
  final source = context.read<CollectionSource>();
  const radius = 250;
  final from = max(0, position - radius);
  final to = min(order.length, position + radius + 1);
  final entries = <AvesEntry>[
    for (var i = from; i < to; i++) library.entryAt(order[i]),
  ];
  final collection = CollectionLens(
    source: source,
    listenToSource: false,
    fixedSelection: entries,
  );
  Navigator.maybeOf(context)?.push(
    MaterialPageRoute(
      settings: const RouteSettings(name: EntryViewerPage.routeName),
      builder: (context) => SelectionProvider<AvesEntry>(
        toSelectableItems: (entry) => entry.toSelectableItems(),
        keyOf: (entry) => entry.id,
        child: EntryViewerPage(
          collection: collection,
          initialEntry: library.entryAt(order[position]),
        ),
      ),
    ),
  );
}
