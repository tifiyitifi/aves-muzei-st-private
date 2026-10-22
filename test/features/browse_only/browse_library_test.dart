import 'package:aves/features/browse_only/model/browse_row.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The browse window: order, de-duplication, month grouping, and the on-demand
/// entry materialization. No database, no collection, no media store read.
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

  AvesEntry entry(
    int id, {
    String dir = '/album',
    String? path,
    int dateTaken = 0,
    bool trashed = false,
    String mime = 'image/jpeg',
    int duration = 0,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: path ?? '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: duration,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  test('the sort date falls back the way the SQL expression does', () {
    final image = entry(1);
    // A present-but-zero capture date wins, as COALESCE does: 1970 is a date,
    // not a missing one.
    image.sourceDateTakenMillis = 0;
    image.dateModifiedMillis = 5000;
    expect(BrowseRow.fromEntry(image).bestDateMillis, 0);

    image.sourceDateTakenMillis = null;
    expect(BrowseRow.fromEntry(image).bestDateMillis, 5000);

    // A null modified date must not read as 0, which would stop the fallback
    // before the added date the platform sorted by.
    image.dateModifiedMillis = null;
    image.dateAddedSecs = 7;
    expect(BrowseRow.fromEntry(image).bestDateMillis, 7000);
  });

  test('keeps arrival order and ignores rows a page repeats', () {
    library.addEntries([entry(1, dateTaken: millis(2024, 3)), entry(2, dateTaken: millis(2024, 2))]);
    // A page boundary can overlap what is already indexed.
    library.addEntries([entry(1, dateTaken: millis(2024, 3)), entry(3, dateTaken: millis(2024, 1))]);

    expect(library.length, 3);
    expect([for (var i = 0; i < library.length; i++) library.rowAt(i).id], [1, 2, 3]);
  });

  test('two collections sharing a content id are two rows', () {
    // Images and videos live in separate tables and number their rows
    // independently, so the same content id is not the same row.
    final image = entry(1);
    final video = entry(2, mime: 'video/mp4');
    image.contentId = 7;
    video.contentId = 7;

    library.addEntries([image, video]);
    expect(library.length, 2);
    expect(library.rowAt(0).uri, isNot(library.rowAt(1).uri));
  });

  test('leaves trashed rows out', () {
    library.addEntries([entry(1), entry(2, trashed: true)]);
    expect(library.length, 1);
    expect(library.rowAt(0).id, 1);
  });

  test('hides rows of hidden albums from the media grid too', () async {
    library.addEntries([entry(1, dir: '/visible'), entry(2, dir: '/hidden')]);
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
    addTearDown(() => settings.hiddenFilters = previous);

    final indexes = library.months.expand((month) => month.indexes).toList();
    expect(indexes, [0]);
  });

  test('narrows the index to videos without touching the database', () {
    library.addEntries([
      entry(1, dateTaken: millis(2024, 3), mime: 'video/mp4', duration: 1000),
      entry(2, dateTaken: millis(2024, 3)),
    ]);

    // The media store reports the kind; browsing must not need the catalogue.
    expect(library.videoIndexes, [0]);
    expect(library.rowAt(0).isVideo, isTrue);
    expect(library.rowAt(1).isVideo, isFalse);
  });

  test('groups the media grid into months, newest first', () {
    library.addEntries([
      entry(1, dateTaken: millis(2024, 3)),
      entry(2, dateTaken: millis(2024, 3, 1)),
      entry(3, dateTaken: millis(2024, 1)),
    ]);

    final months = library.months;
    expect(months.map((v) => (v.year, v.month)), [(2024, 3), (2024, 1)]);
    expect(months.first.indexes, [0, 1]);
    expect(months.last.indexes, [2]);
  });

  test('orders the timeline by date or by name, both directions', () {
    library.addEntries([
      entry(1, path: '/album/b.jpg', dateTaken: millis(2024, 3)),
      entry(2, path: '/album/a.jpg', dateTaken: millis(2024, 1)),
      entry(3, path: '/album/c.jpg', dateTaken: millis(2024, 2)),
    ]);

    List<int> ids(List<int> order) => [for (final index in order) library.rowAt(index).id];

    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: false)), [1, 3, 2]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: true)), [2, 3, 1]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.name, reverse: false)), [2, 1, 3]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.name, reverse: true)), [3, 1, 2]);
  });

  test('materializes an entry on demand and reuses it', () {
    library.addEntries([entry(7, dateTaken: millis(2024, 3))]);

    final first = library.entryAt(0);
    expect(first.uri, 'content://7');
    expect(first.sourceDateTakenMillis, millis(2024, 3));
    expect(first.sourceMimeType, 'image/jpeg');
    // The same instance comes back: tiles and the viewer share it.
    expect(identical(first, library.entryAt(0)), isTrue);
  });

  test('synthetic entry ids are unique and disjoint from database ids', () {
    // The index used to mix two id domains (database ids from the import,
    // position-based ids from the scan), so a viewer or selection keyed by id
    // could resolve to another row. Browse owns the id now.
    library.addEntries([entry(0), entry(5), entry(9)]);

    final ids = [for (var index = 0; index < library.length; index++) library.entryAt(index).id];
    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(ids.length), reason: 'two rows must never share an id');
    expect(ids.every((id) => id < 0), isTrue, reason: 'a synthetic id must not alias a real database id');
  });

  test('clears the window for the handoff back to the collection', () {
    library.addEntries([entry(1)]);
    library.clear();
    expect(library.isEmpty, isTrue);
    expect(library.hasMore, isTrue, reason: 'a cleared window is ready to be read again');
  });
}
