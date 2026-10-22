import 'package:aves/features/browse_only/model/browse_grid_items.dart';
import 'package:aves/features/browse_only/model/browse_scroll_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timeline's month starts, for the scrollbar's label and snapping.
///
/// The geometry is fixed (a header, then rows of tiles), so the map is pure
/// arithmetic over the item list: what matters is that a given scroll offset
/// names the month the user is looking at, and that a drag lands on a month.
void main() {
  const headerExtent = 44.0;
  const rowExtent = 100.0;

  /// September (1 header + 3 rows), August (1 header + 2 rows), July (1 header + 1 row).
  final items = <BrowseGridItem>[
    const BrowseMonthItem(year: 2026, month: 9),
    const BrowseRowItem(start: 0, count: 4),
    const BrowseRowItem(start: 4, count: 4),
    const BrowseRowItem(start: 8, count: 2),
    const BrowseMonthItem(year: 2026, month: 8),
    const BrowseRowItem(start: 10, count: 4),
    const BrowseRowItem(start: 14, count: 4),
    const BrowseMonthItem(year: 2026, month: 7),
    const BrowseRowItem(start: 18, count: 1),
  ];

  final map = BrowseScrollMap.of(items, headerExtent: headerExtent, rowExtent: rowExtent, bottomPadding: 16);

  test('months start where their header does, and the list ends after the last row', () {
    // 44 + 3*100 = 344 for September, then 44 + 2*100 = 244 for August.
    expect([for (final month in map.months) month.offset], [0, 344, 588]);
    expect([for (final month in map.months) month.month], [9, 8, 7]);
    expect(map.totalExtent, 588 + 44 + 100 + 16);
  });

  test('an offset names the month it is in, and clamps outside the list', () {
    expect(map.monthAt(-50)?.month, 9);
    expect(map.monthAt(0)?.month, 9);
    expect(map.monthAt(343.9)?.month, 9);
    expect(map.monthAt(344)?.month, 8);
    expect(map.monthAt(587.9)?.month, 8);
    expect(map.monthAt(588)?.month, 7);
    expect(map.monthAt(100000)?.month, 7);
  });

  test('a drag snaps to the nearer month start', () {
    expect(map.snap(0), 0);
    expect(map.snap(100), 0);
    expect(map.snap(171.9), 0);
    expect(map.snap(172.1), 344);
    expect(map.snap(500), 588);
    expect(map.snap(10000), 588);
  });

  test('crumbs are the month starts as fractions of the list', () {
    final fractions = map.monthFractions();
    expect(fractions.keys.toList(), [0, 344 / 748, 588 / 748]);
    expect([for (final month in fractions.values) month.month], [9, 8, 7]);
  });

  test('an empty list has no months and no fractions', () {
    final empty = BrowseScrollMap.of(const [], headerExtent: headerExtent, rowExtent: rowExtent);
    expect(empty.months, isEmpty);
    expect(empty.totalExtent, 0);
    expect(empty.monthAt(0), isNull);
    expect(empty.snap(12), 12);
    expect(empty.monthFractions(), isEmpty);
  });
}
