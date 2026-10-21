import 'dart:math';

import 'package:aves/features/browse_only/services/browse_library.dart';
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

/// The media grid of the browse-only surface: a timeline of months, or a flat
/// grid when the order is not chronological.
///
/// It renders exactly the rows it is given, in exactly that order. The ordering
/// belongs to [BrowseLibrary] (it owns the index and its caches), so this widget
/// stays a renderer: a sort change is a new list, not a different code path.
class BrowseMediaGrid extends StatefulWidget {
  /// Row positions in display order.
  final List<int> indexes;

  /// Whether to group the rows into month sections (only meaningful when the
  /// order is chronological).
  final bool sectioned;

  /// Shown when there is nothing to render.
  final String? emptyText;

  const new({
    super.key,
    required this.indexes,
    this.sectioned = true,
    this.emptyText,
  });

  @override
  State<BrowseMediaGrid> createState() => _BrowseMediaGridState();
}

/// A month's slice of the displayed order, as positions (not row indexes), so
/// the grid can build a tile without translating back through the sort.
class _SectionRange {
  final int year, month, start, count;

  const new({
    required this.year,
    required this.month,
    required this.start,
    required this.count,
  });
}

class _BrowseMediaGridState extends State<BrowseMediaGrid> {
  List<_SectionRange>? _sections;
  List<int>? _sectionsFor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: browseLibrary,
      builder: (context, child) {
        if (widget.indexes.isEmpty) return _buildEmpty(context);
        if (widget.sectioned) {
          // Sections are derived from the same list instance the library
          // returns for a given order, so identity is a safe cache key.
          if (!identical(_sectionsFor, widget.indexes)) {
            _sections = _sectionsOf(widget.indexes);
            _sectionsFor = widget.indexes;
          }
          return _buildSectionedGrid(context, _sections!);
        }
        return _buildFlatGrid(context);
      },
    );
  }

  Widget _buildEmpty(BuildContext context) => EmptyContent(
    icon: AIcons.image,
    // A view with no rows can read as "nothing here" or as "not imported yet":
    // while the library is still being organized the second is the truth, even
    // for a narrowed view (videos) that has a text of its own.
    text: libraryPhase.isBrowsing && pagedImportStatus.active
        ? context.l10n.sourceStateImporting
        : widget.emptyText ?? context.l10n.browseOnlyEmptyLibrary,
  );

  Widget _buildSectionedGrid(BuildContext context, List<_SectionRange> sections) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = _tileExtent(constraints.maxWidth);
        final columns = (constraints.maxWidth / extent).round().clamp(2, 12);
        return GridTheme(
          extent: extent,
          child: CustomScrollView(
            primary: false,
            slivers: [
              for (final section in sections) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _MonthHeaderDelegate(section: section),
                ),
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 1,
                    crossAxisSpacing: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, offset) => _BrowseTile(
                      order: widget.indexes,
                      position: section.start + offset,
                    ),
                    childCount: section.count,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlatGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = _tileExtent(constraints.maxWidth);
        final columns = (constraints.maxWidth / extent).round().clamp(2, 12);
        return GridTheme(
          extent: extent,
          child: GridView.builder(
            primary: false,
            padding: const EdgeInsets.only(bottom: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
            ),
            itemCount: widget.indexes.length,
            itemBuilder: (context, position) => _BrowseTile(
              order: widget.indexes,
              position: position,
            ),
          ),
        );
      },
    );
  }

  /// Splits the order into consecutive month runs. Chronological order makes
  /// each run contiguous, so a section is a start position plus a length.
  static List<_SectionRange> _sectionsOf(List<int> order) {
    final ranges = <_SectionRange>[];
    int? year, month;
    var start = 0;
    for (var position = 0; position < order.length; position++) {
      final date = DateTime.fromMillisecondsSinceEpoch(browseLibrary.rowAt(order[position]).bestDateMillis);
      if (date.year != year || date.month != month) {
        if (position > 0) {
          ranges.add(_SectionRange(year: year!, month: month!, start: start, count: position - start));
        }
        year = date.year;
        month = date.month;
        start = position;
      }
    }
    if (order.isNotEmpty) {
      ranges.add(_SectionRange(year: year!, month: month!, start: start, count: order.length - start));
    }
    return ranges;
  }

  /// The tile size the collection grid would use, so both surfaces read the
  /// same way. Falls back to four columns on a phone.
  static double _tileExtent(double width) {
    final configured = settings.getTileExtent(CollectionPage.routeName);
    return configured > 0 ? configured : width / 4;
  }
}

class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final _SectionRange section;

  const new({required this.section});

  @override
  double get minExtent => 32;

  @override
  double get maxExtent => 32;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsetsDirectional.only(start: 16),
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        settings.avesLocale.yMMMM(DateTime(section.year, section.month)),
        style: theme.textTheme.titleSmall,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeaderDelegate oldDelegate) =>
      oldDelegate.section.year != section.year || oldDelegate.section.month != section.month;
}

class _BrowseTile extends StatelessWidget {
  /// The displayed order, so the viewer opens on the same sequence the grid
  /// shows and swiping follows the sort.
  final List<int> order;
  final int position;

  const new({
    required this.order,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final index = order[position];
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openBrowseOnlyViewer(context, order, position),
        child: DecoratedThumbnail(
          entry: browseLibrary.entryAt(index),
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
void openBrowseOnlyViewer(BuildContext context, List<int> order, int position) {
  if (position < 0 || position >= order.length) return;
  final source = context.read<CollectionSource>();
  const radius = 250;
  final from = max(0, position - radius);
  final to = min(order.length, position + radius + 1);
  final entries = <AvesEntry>[
    for (var i = from; i < to; i++) browseLibrary.entryAt(order[i]),
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
          initialEntry: browseLibrary.entryAt(order[position]),
        ),
      ),
    ),
  );
}
