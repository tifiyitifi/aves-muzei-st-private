import 'dart:math';

import 'package:aves/features/browse_only/services/browse_library.dart';

/// What the sectioned browse grid renders, in order.
///
/// The month headers are ordinary items here, not pinned slivers. A pinned
/// header of a fixed extent never shrinks, so it keeps painting after its own
/// extent is spent and the viewport pushes every sliver after it down by its
/// height: a section per sliver therefore piles the headers up over the content
/// as they are scrolled past, one header height each, until the screen is
/// headers.
sealed class BrowseGridItem {
  const new();
}

/// A month's header, labelling the rows that follow it.
class BrowseMonthItem extends BrowseGridItem {
  final int year, month;

  const new({required this.year, required this.month});
}

/// A row of at most [count] tiles, starting at [start] in the displayed order.
class BrowseRowItem extends BrowseGridItem {
  final int start, count;

  const new({required this.start, required this.count});
}

/// Flattens the displayed order into the items the grid renders.
///
/// A month is a contiguous run of the order (chronological sorting makes it so),
/// and each run becomes one header followed by rows of [columns] tiles: the last
/// row of a month can be short, so a month's rows never bleed into the next one.
List<BrowseGridItem> browseGridItems(BrowseLibrary library, List<int> order, {required int columns}) {
  assert(columns > 0);
  final items = <BrowseGridItem>[];
  var year = 0;
  var month = 0;
  var start = 0;

  void addMonth(int end) {
    final count = end - start;
    if (count <= 0) return;
    items.add(BrowseMonthItem(year: year, month: month));
    for (var offset = 0; offset < count; offset += columns) {
      items.add(BrowseRowItem(start: start + offset, count: min(columns, count - offset)));
    }
  }

  for (var position = 0; position < order.length; position++) {
    final date = DateTime.fromMillisecondsSinceEpoch(library.rowAt(order[position]).bestDateMillis);
    if (position > 0 && (date.year != year || date.month != month)) {
      addMonth(position);
      start = position;
    }
    year = date.year;
    month = date.month;
  }
  addMonth(order.length);
  return items;
}
