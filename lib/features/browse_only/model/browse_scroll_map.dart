import 'package:aves/features/browse_only/model/browse_grid_items.dart';

/// One month's start, as a pixel offset from the top of the timeline.
class BrowseScrollMonth {
  final double offset;
  final int year, month;

  const new({
    required this.offset,
    required this.year,
    required this.month,
  });

  @override
  String toString() => 'BrowseScrollMonth($year-$month @ $offset)';
}

/// Where each month of a sectioned timeline begins, and how tall the list is.
///
/// A sectioned timeline has a fixed geometry: a header is one height, a row is a
/// tile plus the gap under it. The month starts therefore follow from the item
/// list and two numbers, which is what the scrollbar needs to name the month
/// under the finger and to snap to month starts. Nothing here walks the rows per
/// frame, and nothing materializes an entry: the map is rebuilt only when the
/// item list or the tile size changes.
class BrowseScrollMap {
  final double totalExtent;
  final List<BrowseScrollMonth> months;

  new({
    required this.totalExtent,
    required this.months,
  });

  factory of(
    List<BrowseGridItem> items, {
    required double headerExtent,
    required double rowExtent,
    double bottomPadding = 0,
  }) {
    final months = <BrowseScrollMonth>[];
    var offset = 0.0;
    for (final item in items) {
      switch (item) {
        case BrowseMonthItem(:final year, :final month):
          months.add(BrowseScrollMonth(offset: offset, year: year, month: month));
          offset += headerExtent;
        case BrowseRowItem():
          offset += rowExtent;
      }
    }
    return BrowseScrollMap(totalExtent: offset + bottomPadding, months: months);
  }

  /// The month covering [offset], clamped to the first and last one.
  BrowseScrollMonth? monthAt(double offset) {
    if (months.isEmpty) return null;
    return months[_indexAt(offset)];
  }

  /// The month start nearest to [offset]: a drag lands on a month, not halfway
  /// through one.
  double snap(double offset) {
    if (months.isEmpty) return offset;
    final index = _indexAt(offset);
    final current = months[index].offset;
    if (index + 1 >= months.length) return current;
    final next = months[index + 1].offset;
    return offset - current <= next - offset ? current : next;
  }

  /// The month starts as fractions of the whole list, for the scrollbar's
  /// crumbs. A zero-height list has no fractions to give.
  Map<double, BrowseScrollMonth> monthFractions() {
    if (totalExtent <= 0) return const {};
    return {
      for (final month in months) (month.offset / totalExtent).clamp(0.0, 1.0): month,
    };
  }

  /// Index of the last month starting at or before [offset].
  int _indexAt(double offset) {
    var low = 0;
    var high = months.length - 1;
    var found = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (months[mid].offset <= offset) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }
}
