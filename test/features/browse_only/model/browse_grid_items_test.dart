import 'package:aves/features/browse_only/model/browse_grid_items.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';

/// The sectioned grid's items: a month header, then the rows of its tiles.
///
/// The headers are ordinary items, not pinned slivers (see [browseGridItems]),
/// so what matters here is that a month's rows stay under its own header, and
/// that the rows cover the order exactly once.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  late BrowseLibrary library;

  setUp(() async {
    await setUpServices();
    library = BrowseLibrary();
  });

  tearDown(() {
    library.dispose();
  });

  AvesEntry entry(int id, int dateTakenMillis) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: '/album/$id.jpg',
    contentId: 100 + id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: 'title$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: dateTakenMillis,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  /// A timestamp [minutes] before [newest], so a month's rows stay in it.
  int minutesBefore(DateTime newest, int minutes) => newest.millisecondsSinceEpoch - minutes * 60000;

  List<int> order() => library.mediaIndexes(sort: BrowseMediaSort.date, reverse: false);

  test('a month is a header followed by the rows of its tiles', () {
    library.addEntries([
      for (var i = 0; i < 10; i++) entry(1000 + i, minutesBefore(DateTime.utc(2026, 9, 20), i)),
      for (var i = 0; i < 3; i++) entry(2000 + i, minutesBefore(DateTime.utc(2026, 8, 20), i)),
    ]);

    final items = browseGridItems(library, order(), columns: 4);

    expect(items.first, isA<BrowseMonthItem>().having((v) => v.month, 'month', 9));
    expect(
      items.whereType<BrowseRowItem>().map((row) => (row.start, row.count)).toList(),
      // Four tiles a row, and the short last row of a month stays short.
      [(0, 4), (4, 4), (8, 2), (10, 3)],
    );
    expect(items.whereType<BrowseMonthItem>().map((v) => v.month).toList(), [9, 8]);
  });

  test('the rows cover the order once, in order, and never cross a month', () {
    library.addEntries([
      for (var month = 1; month <= 3; month++)
        for (var i = 0; i < 7; i++) entry(month * 100 + i, minutesBefore(DateTime.utc(2026, month, 20), i)),
    ]);
    final positions = order();

    var headers = 0;
    final placed = <int>[];
    for (final item in browseGridItems(library, positions, columns: 3)) {
      switch (item) {
        case BrowseMonthItem():
          headers++;
        case BrowseRowItem(:final start, :final count):
          expect(count, inInclusiveRange(1, 3));
          final months = {
            for (var position = start; position < start + count; position++) DateTime.fromMillisecondsSinceEpoch(library.rowAt(positions[position]).bestDateMillis).month,
          };
          expect(months, hasLength(1), reason: 'a row never holds rows of two months');
          placed.addAll([for (var position = start; position < start + count; position++) position]);
      }
    }

    expect(headers, 3);
    expect(placed, [for (var position = 0; position < positions.length; position++) position], reason: 'every row is placed once, in order');
  });
}
